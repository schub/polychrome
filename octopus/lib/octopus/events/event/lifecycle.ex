defmodule Octopus.Events.Event.Lifecycle do
  @moduledoc """
  App lifecycle events for managing app selection and deselection.

  These events are sent to apps when they become selected or deselected,
  replacing the direct use of protobuf ControlEvent for app lifecycle management.
  """

  @type event_type :: :app_selected | :app_deselected

  @enforce_keys [:type]
  defstruct [:type]

  @type t :: %__MODULE__{
          type: event_type()
        }

  @doc """
  Creates an app selected lifecycle event.
  """
  def app_selected(), do: %__MODULE__{type: :app_selected}

  @doc """
  Creates an app deselected lifecycle event.
  """
  def app_deselected(), do: %__MODULE__{type: :app_deselected}
end
