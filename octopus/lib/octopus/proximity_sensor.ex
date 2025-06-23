defmodule Octopus.ProximitySensor do
  @moduledoc """
  A GenServer that centralizes proximity sensor readings.

  This module provides:
  - Current values from each sensor
  - Optional smoothed values
  - History of sensor values
  """

  use GenServer
  require Logger

  alias Octopus.Protobuf.ProximityEvent

  # Smoothing factor for exponential moving average (0.0 to 1.0)
  # Lower values = more smoothing, higher values = more responsive
  @default_smoothing_factor 0.1

  # PubSub topic for proximity readings
  @topic "proximity_sensor"

  defmodule State do
    defstruct [
      :smoothing_factor,
      :measurements,
      :smoothed_measurements
    ]
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def handle_proximity_event(%ProximityEvent{} = event) do
    GenServer.cast(__MODULE__, {:proximity_event, event})
  end

  def get_current_values() do
    GenServer.call(__MODULE__, :get_current_values)
  end

  def get_smoothed_values() do
    GenServer.call(__MODULE__, :get_smoothed_values)
  end

  @doc """
  Sets the smoothing factor for exponential moving average.
  Value should be between 0.0 and 1.0.
  Lower values = more smoothing, higher values = more responsive.
  """
  def set_smoothing_factor(factor) when is_float(factor) and factor >= 0.0 and factor <= 1.0 do
    GenServer.cast(__MODULE__, {:set_smoothing_factor, factor})
  end

  def get_smoothing_factor() do
    GenServer.call(__MODULE__, :get_smoothing_factor)
  end

  # GenServer callbacks

  def init(:ok) do
    state = %State{
      smoothing_factor: @default_smoothing_factor,
      measurements: %{},
      smoothed_measurements: %{}
    }

    {:ok, state}
  end

  def handle_cast({:proximity_event, %ProximityEvent{} = event}, %State{} = state) do
    sensor_key = {event.panel_index, event.sensor_index}

    measurements = Map.put(state.measurements, sensor_key, event.distance_mm)

    # Apply exponential moving average for smoothing
    current_smoothed = Map.get(state.smoothed_measurements, sensor_key, event.distance_mm)

    new_smoothed =
      current_smoothed + state.smoothing_factor * (event.distance_mm - current_smoothed)

    smoothed_measurements = Map.put(state.smoothed_measurements, sensor_key, new_smoothed)

    new_state = %State{
      state
      | measurements: measurements,
        smoothed_measurements: smoothed_measurements
    }

    # Broadcast proximity reading for real-time visualization
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:reading, sensor_key, event.distance_mm, System.os_time(:millisecond)}
    )

    Logger.debug(
      "Proximity reading: Panel #{event.panel_index}, Sensor #{event.sensor_index}, " <>
        "Distance #{round(event.distance_mm)}mm, Smoothed #{round(new_smoothed)}mm"
    )

    {:noreply, new_state}
  end

  def handle_cast({:set_smoothing_factor, factor}, state) do
    {:noreply, %State{state | smoothing_factor: factor}}
  end

  def handle_call(:get_current_values, _from, %State{measurements: measurements} = state) do
    {:reply, measurements, state}
  end

  def handle_call(:get_smoothed_values, _from, %State{smoothed_measurements: smoothed} = state) do
    {:reply, smoothed, state}
  end

  def handle_call(:get_smoothing_factor, _from, %State{smoothing_factor: factor} = state) do
    {:reply, factor, state}
  end
end
