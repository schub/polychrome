defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.{Broadcaster, Protobuf, Canvas, AppManager}

  alias Octopus.Protobuf.{
    RGBFrame,
    AudioFrame
  }

  @pubsub_topic "mixer"
  @pubsub_frames [RGBFrame]
  @transition_duration 300
  @transition_frame_time trunc(1000 / 60)

  defmodule State do
    defstruct [
      # Enhanced display system
      # %{app_id => %{rgb_buffer: canvas, grayscale_buffer: canvas, config: %{}}}
      app_displays: %{},
      # List of app_ids to include in mixdown
      selected_apps: [],
      # :rgb | :grayscale | :masked
      output_mode: :rgb,
      # Cached installation info for performance
      display_info: nil,

      # Existing fields (maintained for compatibility)
      rendered_app: nil,
      transition: nil,
      buffer_canvas: Canvas.new(80, 8),
      max_luminance: 255
    ]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # New display buffer management functions

  @doc """
  Creates display buffers for an app with the given configuration.
  """
  def create_display_buffers(app_id, config) do
    GenServer.call(__MODULE__, {:create_display_buffers, app_id, config})
  end

  @doc """
  Updates an app's display buffer with new canvas data.
  """
  def update_app_display(app_id, canvas, mode \\ :rgb, easing_interval_override \\ nil) do
    GenServer.cast(
      __MODULE__,
      {:update_app_display, app_id, canvas, mode, easing_interval_override}
    )
  end

  @doc """
  Returns cached display information for apps to use.
  """
  def get_display_info() do
    GenServer.call(__MODULE__, :get_display_info)
  end

  @doc """
  Sets which apps should be included in the visual mixdown.
  """
  def set_selected_apps(app_ids) do
    GenServer.cast(__MODULE__, {:set_selected_apps, app_ids})
  end

  @doc """
  Sets the output mode for the mixer.
  """
  def set_output_mode(mode) when mode in [:rgb, :grayscale, :masked] do
    GenServer.cast(__MODULE__, {:set_output_mode, mode})
  end

  # Existing frame handling functions (preserved for compatibility)

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

    # Initialize default display info cache for backward compatibility
    display_info = build_display_info(:gapped_panels)

    {:ok, %State{display_info: display_info}}
  end

  # New display buffer management callbacks

  def handle_call({:create_display_buffers, app_id, config}, _from, %State{} = state) do
    # Build layout-specific display info for this app
    layout = Map.get(config, :layout, :gapped_panels)
    display_info = build_display_info(layout)

    width = display_info.width
    height = display_info.height

    # Create buffers based on app configuration
    rgb_buffer = if Map.get(config, :supports_rgb, true), do: Canvas.new(width, height), else: nil

    grayscale_buffer =
      if Map.get(config, :supports_grayscale, false), do: Canvas.new(width, height), else: nil

    app_display = %{
      rgb_buffer: rgb_buffer,
      grayscale_buffer: grayscale_buffer,
      config: config,
      # Store per-app display info
      display_info: display_info
    }

    new_app_displays = Map.put(state.app_displays, app_id, app_display)
    new_state = %State{state | app_displays: new_app_displays}

    {:reply, :ok, new_state}
  end

  def handle_call(:get_display_info, _from, %State{} = state) do
    # Return the global default display info (for backward compatibility)
    # Apps should use their specific display info from their buffer config
    {:reply, state.display_info, state}
  end

  def handle_call({:get_display_info, app_id}, _from, %State{} = state) do
    # Return app-specific display info
    case Map.get(state.app_displays, app_id) do
      %{display_info: display_info} -> {:reply, display_info, state}
      nil -> {:reply, nil, state}
    end
  end

  def handle_cast(
        {:update_app_display, app_id, canvas, mode, easing_interval_override},
        %State{} = state
      ) do
    case Map.get(state.app_displays, app_id) do
      nil ->
        # App not configured yet, ignore update
        {:noreply, state}

      app_display ->
        updated_display =
          case mode do
            :rgb -> %{app_display | rgb_buffer: canvas}
            :grayscale -> %{app_display | grayscale_buffer: canvas}
          end

        new_app_displays = Map.put(state.app_displays, app_id, updated_display)
        new_state = %State{state | app_displays: new_app_displays}

        # If this app is currently selected (single app mode), generate and send frame immediately
        if state.rendered_app == app_id and mode == :rgb do
          display_info = updated_display.display_info
          # Use override easing_interval if provided, otherwise use app's configured value
          easing_interval =
            easing_interval_override || Map.get(updated_display.config, :easing_interval, 0)

          frame = canvas_to_frame(canvas, display_info, easing_interval)
          binary = Protobuf.encode(frame)
          send_frame(binary, frame)
        end

        {:noreply, new_state}
    end
  end

  def handle_cast({:set_selected_apps, app_ids}, %State{} = state) do
    new_state = %State{state | selected_apps: app_ids}
    {:noreply, new_state}
  end

  def handle_cast({:set_output_mode, mode}, %State{} = state) do
    new_state = %State{state | output_mode: mode}
    {:noreply, new_state}
  end

  # Existing callbacks (preserved for compatibility)

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

  # Display info and layout functions (replaces VirtualMatrix functionality)

  # Converts a canvas to frame using layout-aware pixel extraction.
  # Replaces Canvas.to_frame() with layout-specific logic and per-app easing.
  defp canvas_to_frame(canvas, display_info, easing_interval) do
    installation = Octopus.installation()
    panel_count = installation.panel_count()

    # Extract pixels from each panel according to the layout
    panel_canvases =
      for panel_id <- 0..(panel_count - 1) do
        {x_start, x_end} = display_info.panel_range.(panel_id, :x)
        {y_start, y_end} = display_info.panel_range.(panel_id, :y)

        # Extract the panel section from the virtual canvas
        Canvas.cut(canvas, {x_start, y_start}, {x_end, y_end})
      end

    # Join all panel canvases and convert to frame with app-specific easing
    # Reverse the order to match the expected physical layout
    panel_canvases
    |> Enum.reverse()
    |> Enum.reduce(&Canvas.join/2)
    |> Canvas.to_frame(easing_interval: easing_interval)
  end

  defp build_display_info(layout) do
    installation = Octopus.installation()

    # Build layout-specific functions based on layout type
    {panel_range_fn, width} =
      case layout do
        :adjacent_panels ->
          range_fn = fn panel_id, axis ->
            case axis do
              :x ->
                panel_width = installation.panel_width()
                x_offset = panel_id * panel_width
                {x_offset, x_offset + panel_width - 1}

              :y ->
                panel_height = installation.panel_height()
                {0, panel_height - 1}
            end
          end

          # Panels are directly adjacent, no gaps
          calculated_width = installation.panel_count() * installation.panel_width()
          {range_fn, calculated_width}

        :gapped_panels ->
          range_fn = fn panel_id, axis ->
            case axis do
              :x ->
                panel_width = installation.panel_width()
                panel_gap = installation.panel_gap()
                x_offset = panel_id * (panel_width + panel_gap)
                {x_offset, x_offset + panel_width - 1}

              :y ->
                panel_height = installation.panel_height()
                {0, panel_height - 1}
            end
          end

          # Gaps only between panels, not after the last one
          panel_count = installation.panel_count()
          panel_width = installation.panel_width()
          panel_gap = installation.panel_gap()
          calculated_width = panel_count * panel_width + (panel_count - 1) * panel_gap
          {range_fn, calculated_width}

        :gapped_panels_wrapped ->
          range_fn = fn panel_id, axis ->
            case axis do
              :x ->
                panel_width = installation.panel_width()
                panel_gap = installation.panel_gap()
                x_offset = panel_id * (panel_width + panel_gap)
                {x_offset, x_offset + panel_width - 1}

              :y ->
                panel_height = installation.panel_height()
                {0, panel_height - 1}
            end
          end

          # Gaps between panels AND after the last panel for wrapping
          panel_count = installation.panel_count()
          panel_width = installation.panel_width()
          panel_gap = installation.panel_gap()
          calculated_width = panel_count * (panel_width + panel_gap)
          {range_fn, calculated_width}
      end

    panel_at_coord_fn = fn x, y ->
      panel_count = installation.panel_count()

      Enum.find(0..(panel_count - 1), fn panel_id ->
        {start_x, end_x} = panel_range_fn.(panel_id, :x)
        {start_y, end_y} = panel_range_fn.(panel_id, :y)
        x >= start_x and x <= end_x and y >= start_y and y <= end_y
      end) || :not_found
    end

    %{
      layout: layout,
      width: width,
      height: installation.panel_height(),
      panel_width: installation.panel_width(),
      panel_height: installation.panel_height(),
      panel_count: installation.panel_count(),
      panel_gap: installation.panel_gap(),
      panel_range: panel_range_fn,
      panel_at_coord: panel_at_coord_fn
    }
  end

  @doc """
  Returns app-specific display information based on the app's layout configuration.
  """
  def get_app_display_info(app_id) do
    GenServer.call(__MODULE__, {:get_display_info, app_id})
  end
end
