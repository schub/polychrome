defmodule Octopus.Events.Event.Controller do
  @moduledoc """
  Domain event for user input in the Octopus system.

  This represents controller input events in a clean, domain-focused format,
  abstracted from the underlying protobuf network protocol.

  Event Types:
  - Button events: Screen buttons 1-12
  - Joystick events: Analog stick movement and action buttons
  """

  defstruct [:type, :button, :action, :joystick, :direction, :joy_button]

  @type t ::
          %__MODULE__{
            # Button events (screen buttons 1-12)
            type: :button,
            button: 1..12,
            action: :press | :release,
            joystick: nil,
            direction: nil,
            joy_button: nil
          }
          | %__MODULE__{
              # Joystick movement events
              type: :joystick,
              button: nil,
              action: nil,
              joystick: 1..2,
              direction: :left | :right | :up | :down | :center,
              joy_button: nil
            }
          | %__MODULE__{
              # Joystick button events
              type: :joystick,
              button: nil,
              action: :press | :release,
              joystick: 1..2,
              direction: nil,
              joy_button: :a | :b | :menu
            }

  @doc """
  Validates a controller event structure.
  """
  def validate(%__MODULE__{type: :button, button: button, action: action})
      when button in 1..12 and action in [:press, :release] do
    :ok
  end

  def validate(%__MODULE__{type: :joystick, joystick: joystick, direction: direction})
      when joystick in 1..2 and direction in [:left, :right, :up, :down, :center] do
    :ok
  end

  def validate(%__MODULE__{
        type: :joystick,
        joystick: joystick,
        joy_button: joy_button,
        action: action
      })
      when joystick in 1..2 and joy_button in [:a, :b, :menu] and action in [:press, :release] do
    :ok
  end

  def validate(_), do: {:error, :invalid_controller_event}
end
