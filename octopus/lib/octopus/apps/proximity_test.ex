defmodule Octopus.Apps.ProximityTest do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Protobuf.ProximityEvent
  alias Octopus.Canvas

  defmodule State do
    defstruct [:min_distance, :max_distance, :measurements]
  end

  @fps 30
  @frame_time_ms trunc(1000 / @fps)

  def name(), do: "Proximity Test"

  def config_schema() do
    %{
      min_distance: {"Min Distance [mm]", :int, %{default: 50, min: 0, max: 50_000}},
      max_distance: {"Max Distance [mm]", :int, %{default: 5_000, min: 0, max: 50_000}}
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

  def init(config) do
    # Start the timer for rendering
    :timer.send_interval(@frame_time_ms, :tick)

    {:ok,
     %State{
       min_distance: config.min_distance,
       max_distance: config.max_distance,
       measurements: %{}
     }}
  end

  def handle_info(:tick, %State{} = state) do
    state
    |> render_proximity_data()
    |> Canvas.to_frame()
    |> send_frame()

    {:noreply, state}
  end

  def handle_proximity(
        %ProximityEvent{
          panel_index: panel_index,
          sensor_index: sensor_index,
          distance_mm: distance
        },
        %State{measurements: measurements, min_distance: min, max_distance: max} = state
      )
      when distance >= min and distance <= max do
    # Logger.info(
    #   "Proximity measurement: Panel #{panel_index}, Sensor #{sensor_index}, Distance #{round(distance)}mm"
    # )

    measurements = Map.put(measurements, {panel_index, sensor_index}, distance)

    {:noreply, %State{state | measurements: measurements}}
  end

  def handle_proximity(
        %ProximityEvent{
          panel_index: panel_index,
          sensor_index: sensor_index,
          distance_mm: distance
        },
        state
      ) do
    # Logger.debug(
    #   "Proximity measurement out of range: Panel #{panel_index}, Sensor #{sensor_index}, Distance #{round(distance)}mm"
    # )

    {:noreply, state}
  end

  def handle_proximity(event, state) do
    Logger.warning("Unhandled proximity event: #{inspect(event)}")
    {:noreply, state}
  end

  defp render_proximity_data(%State{
         measurements: measurements,
         min_distance: min,
         max_distance: max
       }) do
    canvas = Canvas.new(96, 8)

    Enum.reduce(measurements, canvas, fn {{panel_index, sensor_index}, distance}, acc_canvas ->
      brightness_ratio = 1.0 - (distance - min) / (max - min)
      brightness_value = trunc(brightness_ratio * 100)

      %Chameleon.RGB{r: r, g: g, b: b} =
        Chameleon.HSV.new(280, 100, brightness_value)
        |> Chameleon.convert(Chameleon.RGB)

      color = {r, g, b}

      panel_start_x = (panel_index - 1) * 8
      side_width = 4

      # Sensor 0 = left side (x: 0-3), Sensor 1 = right side (x: 4-7)
      x_start = panel_start_x + if sensor_index == 0, do: 0, else: 4
      x_end = x_start + side_width - 1

      for x <- x_start..x_end,
          y <- 0..7,
          reduce: acc_canvas do
        canvas -> Canvas.put_pixel(canvas, {x, y}, color)
      end
    end)
  end
end
