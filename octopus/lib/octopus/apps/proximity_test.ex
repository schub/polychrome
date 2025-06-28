defmodule Octopus.Apps.ProximityTest do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  defmodule State do
    defstruct [:min_distance, :max_distance, :measurements, :smoothed_measurements]
  end

  @fps 30
  @frame_time_ms trunc(1000 / @fps)

  # Smoothing factor for exponential moving average (0.0 to 1.0)
  # Lower values = more smoothing, higher values = more responsive
  # @smoothing_factor 0.1

  def name(), do: "Proximity Test"

  def config_schema() do
    %{
      min_distance: {"Min Distance [mm]", :int, %{default: 500, min: 0, max: 50_000}},
      max_distance: {"Max Distance [mm]", :int, %{default: 3_000, min: 0, max: 50_000}}
    }
  end

  def get_config(state) do
    %{
      min_distance: state.min_distance,
      max_distance: state.max_distance
    }
  end

  def handle_config_change(config, state) do
    {:ok, %State{state | min_distance: config.min_distance, max_distance: config.max_distance}}
  end

  def app_init(config) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Start the timer for rendering
    :timer.send_interval(@frame_time_ms, :tick)

    {:ok,
     %State{
       min_distance: config.min_distance,
       max_distance: config.max_distance,
       measurements: %{},
       smoothed_measurements: %{}
     }}
  end

  def handle_info(:tick, %State{} = state) do
    state
    |> render_proximity_data()
    |> Octopus.App.update_display()

    {:noreply, state}
  end

  def handle_event(
        %ProximityEvent{
          panel: panel,
          sensor: sensor,
          distance_mm: distance
        },
        %State{
          measurements: measurements,
          smoothed_measurements: _smoothed,
          min_distance: min,
          max_distance: max
        } = state
      )
      when distance >= min and distance <= max do
    Logger.info(
      "Proximity measurement: Panel #{panel}, Sensor #{sensor}, Distance #{round(distance)}mm"
    )

    sensor_key = {panel, sensor}
    measurements = Map.put(measurements, sensor_key, distance)

    # # Apply exponential moving average for smoothing
    # current_smoothed = Map.get(smoothed, sensor_key, distance)
    # new_smoothed = current_smoothed + @smoothing_factor * (distance - current_smoothed)
    # smoothed_measurements = Map.put(smoothed, sensor_key, new_smoothed)

    {:noreply, %State{state | measurements: measurements, smoothed_measurements: measurements}}
  end

  def handle_event(
        %ProximityEvent{
          panel: panel,
          sensor: sensor,
          distance_mm: distance
        },
        state
      ) do
    Logger.debug(
      "Proximity measurement out of range: Panel #{panel}, Sensor #{sensor}, Distance #{round(distance)}mm"
    )

    {:noreply, state}
  end

  def handle_event(event, state) do
    Logger.warning("Unhandled proximity event: #{inspect(event)}")
    {:noreply, state}
  end

  defp render_proximity_data(%State{
         smoothed_measurements: smoothed_measurements,
         min_distance: min,
         max_distance: max
       }) do
    # Get display info to calculate canvas size dynamically
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)

    Enum.reduce(smoothed_measurements, canvas, fn {{panel, sensor}, distance}, acc_canvas ->
      brightness_ratio = 1.0 - (distance - min) / (max - min)
      brightness_value = trunc(brightness_ratio * 100)

      %Chameleon.RGB{r: r, g: g, b: b} =
        Chameleon.HSV.new(280, 100, brightness_value)
        |> Chameleon.convert(Chameleon.RGB)

      color = {r, g, b}

      # Calculate panel positioning dynamically based on display info
      panel_start_x = (panel - 1) * display_info.panel_width
      sensor_width = div(display_info.panel_width, 2)

      # Sensor 0 = left side, Sensor 1 = right side of each panel
      x_start = panel_start_x + if sensor == 0, do: 0, else: sensor_width
      x_end = x_start + sensor_width - 1

      for x <- x_start..x_end,
          y <- 0..(display_info.panel_height - 1),
          reduce: acc_canvas do
        canvas -> Canvas.put_pixel(canvas, {x, y}, color)
      end
    end)
  end
end
