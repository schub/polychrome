defmodule Octopus.Events.Event.Audio do
  @moduledoc """
  Domain event representing audio analysis data for audio-reactive lighting effects.

  This event contains frequency analysis data (bass, mid, high) from external
  audio analyzers and is used to drive audio-reactive lighting programs.
  """

  @enforce_keys [:bass, :mid, :high, :timestamp]
  defstruct [:bass, :mid, :high, :timestamp]

  @type t :: %__MODULE__{
          bass: float(),
          mid: float(),
          high: float(),
          timestamp: integer()
        }

  @doc """
  Validates an audio event ensuring all frequency values are present and valid.
  """
  def validate(%__MODULE__{bass: bass, mid: mid, high: high})
      when is_float(bass) and is_float(mid) and is_float(high) do
    :ok
  end

  def validate(_), do: {:error, :invalid_audio_event}

  @doc """
  Returns the overall intensity of the audio event as the maximum frequency value.
  """
  def intensity(%__MODULE__{bass: bass, mid: mid, high: high}) do
    max(bass, max(mid, high))
  end

  @doc """
  Returns the dominant frequency band (:bass, :mid, or :high).
  """
  def dominant_frequency(%__MODULE__{bass: bass, mid: mid, high: high}) do
    cond do
      bass >= mid and bass >= high -> :bass
      mid >= high -> :mid
      true -> :high
    end
  end

  @doc """
  Returns a normalized frequency spectrum as a tuple {bass, mid, high}
  where each value is between 0.0 and 1.0 based on the maximum value.
  """
  def normalized_spectrum(%__MODULE__{bass: bass, mid: mid, high: high}) do
    max_val = max(bass, max(mid, high))

    if max_val > 0 do
      {bass / max_val, mid / max_val, high / max_val}
    else
      {0.0, 0.0, 0.0}
    end
  end
end
