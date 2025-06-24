defmodule Octopus.Apps.BeakTest do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Protobuf.{SynthFrame, SynthAdsrConfig, SynthConfig}
  alias Octopus.Canvas
  alias Octopus.Events.Event.Controller, as: ControllerEvent

  defmodule State do
    defstruct [:index, :color, :canvas]
  end

  def name(), do: "Beak"

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    {:ok, %State{canvas: Canvas.new(80, 8)}}
  end

  def handle_input(
        %ControllerEvent{type: :button, action: :press, button: button},
        %State{} = state
      )
      when button >= 1 and button <= 10 do
    channel = button

    send_frame(%SynthFrame{
      event_type: :NOTE_ON,
      channel: channel,
      config: %SynthConfig{
        wave_form: :SQUARE,
        gain: 1,
        adsr_config: %SynthAdsrConfig{
          attack: 0.01,
          decay: 0,
          sustain: 1,
          release: 0.2
        },
        filter_adsr_config: %SynthAdsrConfig{
          attack: 0,
          decay: 0.1,
          sustain: 0.2,
          release: 0.4
        },
        filter_type: :LOWPASS,
        resonance: 2,
        cutoff: 5000
      },
      duration_ms: 500,
      note: 60 + channel,
      velocity: 1
    })

    top_left = {(channel - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    canvas =
      state.canvas
      |> Canvas.fill_rect(top_left, bottom_right, {255, 255, 255})

    # Use new unified display API instead of Canvas.to_frame() |> send_frame()
    Octopus.App.update_display(canvas)
    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(%ControllerEvent{type: :button, action: :release, button: button}, state)
      when button >= 1 and button <= 10 do
    channel = button

    top_left = {(channel - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    canvas =
      state.canvas
      |> Canvas.clear_rect(top_left, bottom_right)

    # Use new unified display API instead of Canvas.to_frame() |> send_frame()
    Octopus.App.update_display(canvas)
    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
