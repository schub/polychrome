defmodule Octopus.Events.Event.Proximity do
  @moduledoc """
  Domain event for proximity sensor readings in the Octopus system.

  This represents proximity sensor events in a clean, domain-focused format,
  abstracted from the underlying protobuf network protocol.

  Proximity sensors detect objects/people approaching the LED panels and provide
  distance measurements in millimeters.
  """

  defstruct [
    :panel,
    :sensor,
    :distance,
    :distance_sma,
    :distance_ema,
    :distance_median,
    :distance_combined,
    :timestamp
  ]

  @type t :: %__MODULE__{
          # Panel identifier (1-based indexing)
          panel: pos_integer(),
          # Sensor identifier within the panel (0-based indexing, typically 0 or 1)
          sensor: non_neg_integer(),
          # Distance measurement in millimeters (raw value)
          distance: float(),
          # Simple moving average smoothed distance (nil if not processed)
          distance_sma: float() | nil,
          # Exponential moving average smoothed distance (nil if not processed)
          distance_ema: float() | nil,
          # Median filtered distance (nil if not processed)
          distance_median: float() | nil,
          # Combined median + EMA filtered distance (nil if not processed)
          distance_combined: float() | nil,
          # When the measurement was taken (system time)
          timestamp: integer()
        }
end
