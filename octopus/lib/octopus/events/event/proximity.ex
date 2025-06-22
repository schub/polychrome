defmodule Octopus.Events.Event.Proximity do
  @moduledoc """
  Domain event for proximity sensor readings in the Octopus system.

  This represents proximity sensor events in a clean, domain-focused format,
  abstracted from the underlying protobuf network protocol.

  Proximity sensors detect objects/people approaching the LED panels and provide
  distance measurements in millimeters.
  """

  defstruct [:panel, :sensor, :distance_mm, :timestamp]

  @type t :: %__MODULE__{
          # Panel identifier (1-based indexing)
          panel: pos_integer(),
          # Sensor identifier within the panel (0-based indexing, typically 0 or 1)
          sensor: non_neg_integer(),
          # Distance measurement in millimeters
          distance_mm: float(),
          # When the measurement was taken (system time)
          timestamp: integer()
        }

  @doc """
  Validates a proximity event structure.
  """
  def validate(%__MODULE__{panel: panel, sensor: sensor, distance_mm: distance})
      when is_integer(panel) and panel > 0 and
             is_integer(sensor) and sensor >= 0 and
             is_number(distance) and distance >= 0.0 do
    :ok
  end

  def validate(_), do: {:error, :invalid_proximity_event}

  @doc """
  Checks if the proximity reading is within a specified range.
  """
  def in_range?(%__MODULE__{distance_mm: distance}, min_distance, max_distance)
      when is_number(min_distance) and is_number(max_distance) do
    distance >= min_distance and distance <= max_distance
  end

  @doc """
  Returns a sensor identifier tuple for easy grouping/indexing.
  """
  def sensor_id(%__MODULE__{panel: panel, sensor: sensor}) do
    {panel, sensor}
  end

  @doc """
  Calculates the normalized distance as a ratio between 0.0 and 1.0.

  - 0.0 = at min_distance (closest)
  - 1.0 = at max_distance (furthest)

  Values outside the range are clamped to 0.0-1.0.
  """
  def normalized_distance(%__MODULE__{distance_mm: distance}, min_distance, max_distance)
      when is_number(min_distance) and is_number(max_distance) and max_distance > min_distance do
    ratio = (distance - min_distance) / (max_distance - min_distance)
    max(0.0, min(1.0, ratio))
  end

  @doc """
  Calculates proximity intensity (inverse of normalized distance).

  - 1.0 = at min_distance (closest, highest intensity)
  - 0.0 = at max_distance (furthest, lowest intensity)
  """
  def intensity(%__MODULE__{} = event, min_distance, max_distance) do
    1.0 - normalized_distance(event, min_distance, max_distance)
  end
end
