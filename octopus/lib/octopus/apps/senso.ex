defmodule Octopus.Apps.Senso do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Protobuf.{SynthFrame, ControlEvent, AudioFrame, SynthConfig, SynthAdsrConfig}

  @num_windows 10
  @first_squence_len 3
  @state_time_delta 100
  @time_between_elements_ms 500

  @synth_config %SynthConfig{
    wave_form: :SQUARE,
    gain: 1,
    adsr_config: %SynthAdsrConfig{
      attack: 0.01,
      decay: 0,
      sustain: 1,
      release: 0.2
    }
  }

  defmodule State do
    defstruct expected_sequence: [],
              index: 0,
              successes: 0,
              input_blocked: true
  end

  def name(), do: "Senso"

  def app_init(_args) do
    state = %State{
      expected_sequence: generate_sequence(@first_squence_len),
      index: 0,
      successes: 0,
      input_blocked: true
    }

    send(self(), :run)

    {:ok, state}
  end

  defp generate_sequence(len) do
    for _ <- 1..len, do: Enum.random(1..@num_windows)
  end

  def handle_info(:run, %State{expected_sequence: expected_sequence, index: index} = state)
      when index < length(expected_sequence) do
    window = Enum.at(expected_sequence, index)

    top_left = {(window - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    Canvas.new(80, 8)
    |> Canvas.fill_rect(top_left, bottom_right, get_color(window))
    |> Canvas.to_frame()
    |> send_frame()

    %SynthFrame{
      event_type: :NOTE_ON,
      channel: window,
      note: 60 + window - 1,
      config: @synth_config,
      duration_ms: @time_between_elements_ms,
      velocity: 1
    }
    |> send_frame()

    :timer.sleep(@time_between_elements_ms)

    Canvas.new(80, 8)
    |> Canvas.to_frame()
    |> send_frame()

    %SynthFrame{
      event_type: :NOTE_OFF,
      channel: window,
      note: 60 + window - 1
    }
    |> send_frame()

    :timer.sleep((@time_between_elements_ms / 2) |> trunc())

    send(self(), :run)
    {:noreply, %State{state | index: state.index + 1, input_blocked: true}}
  end

  ## finished playing sequence
  def handle_info(:run, %State{} = state) do
    {:noreply, %State{state | index: 0, input_blocked: false}}
  end

  def handle_info(:reset, _state) do
    newState = %State{
      expected_sequence: generate_sequence(@first_squence_len),
      index: 0,
      successes: 0,
      input_blocked: true
    }

    send(self(), :run)

    {:noreply, newState}
  end

  def handle_info(:success, %State{} = state) do
    newState = %State{
      expected_sequence: state.expected_sequence ++ generate_sequence(1),
      index: 0,
      successes: state.successes + 1,
      input_blocked: true
    }

    :timer.sleep(@time_between_elements_ms)

    send(self(), :run)

    {:noreply, newState}
  end

  def handle_event(_input_event, %State{input_blocked: true} = state) do
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button},
        %State{} = state
      )
      when button >= 1 and button <= @num_windows do
    btn_num = button

    top_left = {(btn_num - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    Canvas.new(80, 8)
    |> Canvas.fill_rect(top_left, bottom_right, get_color(btn_num))
    |> Canvas.to_frame()
    |> send_frame()

    %SynthFrame{
      event_type: :NOTE_ON,
      channel: btn_num,
      note: 60 + btn_num - 1,
      config: @synth_config,
      duration_ms: 1000,
      velocity: 1
    }
    |> send_frame()

    {:noreply, state}
  end

  def handle_event(%InputEvent{type: :button, action: :release, button: button}, state)
      when button >= 1 and button <= @num_windows do
    btn_num = button

    top_left = {(btn_num - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    Canvas.new(80, 8)
    |> Canvas.clear_rect(top_left, bottom_right)
    |> Canvas.to_frame()
    |> send_frame()

    %SynthFrame{
      event_type: :NOTE_OFF,
      channel: btn_num,
      note: 60 + btn_num - 1
    }
    |> send_frame()

    success = btn_num == Enum.at(state.expected_sequence, state.index)

    increment =
      if !success do
        display_fail()
        send(self(), :reset)
        0
      else
        1
      end

    finished = state.index + increment >= length(state.expected_sequence)

    if finished do
      display_success()
      send(self(), :success)
    end

    block_input = finished || !success

    {:noreply, %State{state | index: state.index + increment, input_blocked: block_input}}
  end

  def handle_event(%ControlEvent{type: :APP_SELECTED}, state) do
    Enum.map(1..@num_windows, fn channel ->
      %SynthFrame{
        event_type: :CONFIG,
        channel: channel,
        note: 60,
        config: @synth_config,
        duration_ms: 10
      }
      |> send_frame()
    end)

    send(self(), :run)
    {:noreply, %State{state | input_blocked: true}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp get_color(num) do
    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new((num / 10 * 100) |> trunc(), 100, 100) |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end

  def display_fail() do
    :timer.sleep(200)

    %AudioFrame{
      uri: "file://corrosion15.wav",
      channel: 5
    }
    |> send_frame()

    canvas =
      Canvas.new(80, 8)

    canvas |> Canvas.fill_rect({0, 0}, {79, 7}, {255, 0, 0}) |> Canvas.to_frame() |> send_frame()
    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Canvas.to_frame() |> send_frame()
    :timer.sleep(@state_time_delta)
    canvas |> Canvas.fill_rect({0, 0}, {79, 7}, {255, 0, 0}) |> Canvas.to_frame() |> send_frame()
    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Canvas.to_frame() |> send_frame()
    :timer.sleep((@time_between_elements_ms / 2) |> trunc())
  end

  def display_success() do
    :timer.sleep(200)

    %AudioFrame{
      uri: "file://corrosion14.wav",
      channel: 5
    }
    |> send_frame()

    canvas =
      Canvas.new(80, 8)

    canvas |> Canvas.fill_rect({0, 0}, {79, 7}, {0, 255, 0}) |> Canvas.to_frame() |> send_frame()
    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Canvas.to_frame() |> send_frame()
    :timer.sleep(@state_time_delta)
    canvas |> Canvas.fill_rect({0, 0}, {79, 7}, {0, 255, 0}) |> Canvas.to_frame() |> send_frame()
    :timer.sleep(@state_time_delta)
    canvas |> Canvas.clear() |> Canvas.to_frame() |> send_frame()
    :timer.sleep((@time_between_elements_ms / 2) |> trunc())
  end
end
