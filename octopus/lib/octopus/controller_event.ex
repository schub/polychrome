defmodule Octopus.ControllerEvent do
  @moduledoc """
  Internal event structure for user input in the Octopus system.

  This replaces the protobuf InputEvent format internally while maintaining
  protobuf compatibility at the network boundary.

  Event Types:
  - Button events: Screen buttons 1-12
  - Joystick events: Analog stick movement and action buttons
  """

  defstruct [:type, :button, :action, :value, :joystick, :direction, :joy_button]

  @type t ::
          %__MODULE__{
            # Button events (screen buttons 1-12)
            type: :button,
            button: 1..12,
            action: :press | :release,
            value: nil,
            joystick: nil,
            direction: nil,
            joy_button: nil
          }
          | %__MODULE__{
              # Joystick movement events
              type: :joystick,
              button: nil,
              action: nil,
              value: nil,
              joystick: 1..2,
              direction: :left | :right | :up | :down | :center,
              joy_button: nil
            }
          | %__MODULE__{
              # Joystick button events
              type: :joystick,
              button: nil,
              action: :press | :release,
              value: nil,
              joystick: 1..2,
              direction: nil,
              joy_button: :a | :b | :menu
            }
end
