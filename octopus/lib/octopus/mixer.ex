defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.{Broadcaster, Protobuf, AppSupervisor, Canvas, KioskModeManager, AppManager}

  alias Octopus.Protobuf.{
    RGBFrame,
    ProximityEvent,
    SoundToLightControlEvent,
    AudioFrame
  }

  alias Octopus.ControllerEvent

  @pubsub_topic "mixer"
  @pubsub_frames [RGBFrame]
  @transition_duration 300
  @transition_frame_time trunc(1000 / 60)

  defmodule State do
    defstruct rendered_app: nil,
              transition: nil,
              buffer_canvas: Canvas.new(80, 8),
              max_luminance: 255,
              last_input: 0
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def handle_frame(app_id, %RGBFrame{} = frame) do
    # Split RGB frames to avoid UPD fragmenting. Can be removed when we fix the fragmenting in the firmware
    Protobuf.split_and_encode(frame)
    |> Enum.each(fn binary ->
      send_frame(binary, frame, app_id)
    end)
  end

  def handle_frame(app_id, %{} = frame) do
    # encode the frame in the app process, so any encoding errors get raised there
    Protobuf.encode(frame)
    |> send_frame(frame, app_id)
  end

  def handle_canvas(app_id, canvas) do
    GenServer.cast(__MODULE__, {:new_canvas, {app_id, canvas}})
  end

  defp send_frame(binary, frame, app_id) do
    GenServer.cast(__MODULE__, {:new_frame, {app_id, binary, frame}})
  end

  def handle_event(%{} = event) do
    GenServer.cast(__MODULE__, {:event, event})
  end

  @doc """
  Subscribes to the mixer topic.

  Published messages:

  * `{:mixer, {:frame, %Octopus.Protobuf.Frame{} = frame}}` - a new frame was received from the selected app
  * `{:mixer, {:config, config}}` - mixer configuration changed
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @pubsub_topic)
  end

  def init(:ok) do
    # Subscribe to AppManager events to update visual rendering
    AppManager.subscribe()

    state = %State{
      last_input: System.os_time(:second)
    }

    {:ok, state}
  end

  def handle_cast({:new_frame, {app_id, binary, f}}, %State{rendered_app: rendered_app} = state) do
    case rendered_app do
      {^app_id, _} -> send_frame(binary, f)
      {_, ^app_id} -> send_frame(binary, f)
      ^app_id -> send_frame(binary, f)
      _ -> :noop
    end

    {:noreply, state}
  end

  def handle_cast(
        {:new_canvas, {left_app_id, canvas}},
        %State{rendered_app: {left_app_id, _}} = state
      ) do
    handle_new_canvas(state, canvas, {0, 0})
  end

  def handle_cast(
        {:new_canvas, {right_app_id, canvas}},
        %State{rendered_app: {_, right_app_id}} = state
      ) do
    handle_new_canvas(state, canvas, {40, 0})
  end

  def handle_cast({:new_canvas, _}, state), do: {:noreply, state}

  def handle_cast({:event, %ControllerEvent{} = controller_event}, %State{} = state) do
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, controller_event)
    KioskModeManager.handle_input(controller_event)

    {:noreply, %State{state | last_input: System.os_time(:second)}}
  end

  def handle_cast({:event, %SoundToLightControlEvent{} = stl_event}, %State{} = state) do
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, stl_event)
    {:noreply, state}
  end

  def handle_cast({:event, %ProximityEvent{} = event}, %State{} = state) do
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, event)
    {:noreply, state}
  end

  def handle_cast(:stop_audio_playback, state) do
    do_stop_audio_playback()
    {:noreply, state}
  end

  # Handle app selection changes from AppManager
  def handle_info({:app_manager, {:selected_app, selected_app}}, %State{} = state) do
    case selected_app do
      # Dual-side apps render immediately without transitions
      {_, _} ->
        state = %State{state | rendered_app: selected_app, transition: nil}
        {:noreply, state}

      # Single apps use transitions
      _ ->
        case state.transition do
          # No current transition - start new transition
          nil ->
            state = %State{state | transition: {:out, @transition_duration}}
            schedule_transition()
            {:noreply, state}

          # Already transitioning out - keep transitioning
          {:out, _} ->
            {:noreply, state}

          # Transitioning in - reverse to transition out
          {:in, time_left} ->
            state = %State{state | transition: {:out, @transition_duration - time_left}}
            {:noreply, state}
        end
    end
  end

  # Handle app lifecycle events from AppManager (no action needed, just ignore)
  def handle_info({:app_manager, {:app_lifecycle, _app_id, _event}}, %State{} = state) do
    {:noreply, state}
  end

  ### App Transitions ###
  # Implemented with a simple state machine that is represented by the `transition` field in the state.
  # Possible values are `{:in, time_left}`, `{:out, time_left}` and `nil`.
  # Transitions are now triggered by AppManager selection changes.

  def handle_info(:transition, %State{transition: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time}} = state) when time <= 0 do
    selected_app = AppManager.get_selected_app()

    state = %State{
      state
      | rendered_app: selected_app,
        transition: {:in, @transition_duration}
    }

    Broadcaster.set_luminance(0)

    schedule_transition()

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time}} = state) do
    state = %State{
      state
      | transition: {:out, time - @transition_frame_time}
    }

    (Easing.cubic_in(time / @transition_duration) * state.max_luminance)
    |> round()
    |> Broadcaster.set_luminance()

    schedule_transition()

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:in, time}} = state) when time <= 0 do
    state = %State{state | transition: nil}
    Broadcaster.set_luminance(state.max_luminance)

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:in, time}} = state) do
    selected_app = AppManager.get_selected_app()

    state = %State{
      state
      | transition: {:in, time - @transition_frame_time},
        rendered_app: selected_app
    }

    ((1 - Easing.cubic_out(time / @transition_duration)) * state.max_luminance)
    |> round()
    |> Broadcaster.set_luminance()

    schedule_transition()

    {:noreply, state}
  end

  ### End App Transitions ###

  defp send_frame(binary, %frame_type{} = frame) do
    if frame_type in @pubsub_frames do
      Phoenix.PubSub.broadcast(Octopus.PubSub, @pubsub_topic, {:mixer, {:frame, frame}})
    end

    Broadcaster.send_binary(binary)
  end

  defp schedule_transition() do
    Process.send_after(self(), :transition, @transition_frame_time)
  end

  defp handle_new_canvas(state, canvas, offset) do
    buffer_canvas =
      state.buffer_canvas
      |> Canvas.clear()
      |> Canvas.overlay(canvas, offset: offset)

    frame = buffer_canvas |> Canvas.to_frame()
    binary = Protobuf.encode(frame)
    send_frame(binary, frame)

    {:noreply, %State{state | buffer_canvas: buffer_canvas}}
  end

  defp do_stop_audio_playback() do
    for channel <- 1..8 do
      %AudioFrame{
        channel: channel,
        stop: true
      }
      |> Protobuf.encode()
      |> Broadcaster.send_binary()
    end
  end
end
