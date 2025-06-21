defmodule Octopus.Events.Factory do
  @moduledoc """
  Factory for creating domain events from protobuf events.

  This module centralizes the conversion logic between network protocol formats
  (protobuf) and clean domain events. This keeps protocol-specific knowledge
  out of the domain event modules themselves.
  """

  alias Octopus.Events.Event.{Controller, Proximity, Audio}
  alias Octopus.Protobuf.{InputEvent, ProximityEvent, SoundToLightControlEvent}

  @doc """
  Creates a Controller domain event from a protobuf InputEvent.

  Converts the protobuf format to the internal ControllerEvent format,
  handling the semantic mapping from low-level protobuf types to
  domain-meaningful event structures.
  """
  def create_controller_event(%InputEvent{type: :BUTTON_1, value: value}),
    do: %Controller{type: :button, button: 1, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_2, value: value}),
    do: %Controller{type: :button, button: 2, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_3, value: value}),
    do: %Controller{type: :button, button: 3, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_4, value: value}),
    do: %Controller{type: :button, button: 4, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_5, value: value}),
    do: %Controller{type: :button, button: 5, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_6, value: value}),
    do: %Controller{type: :button, button: 6, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_7, value: value}),
    do: %Controller{type: :button, button: 7, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_8, value: value}),
    do: %Controller{type: :button, button: 8, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_9, value: value}),
    do: %Controller{type: :button, button: 9, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_10, value: value}),
    do: %Controller{type: :button, button: 10, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_11, value: value}),
    do: %Controller{type: :button, button: 11, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_12, value: value}),
    do: %Controller{type: :button, button: 12, action: value_to_action(value)}

  # Joystick movement events
  def create_controller_event(%InputEvent{type: :AXIS_X_1, value: value}) when value < 0,
    do: %Controller{type: :joystick, joystick: 1, direction: :left}

  def create_controller_event(%InputEvent{type: :AXIS_X_1, value: value}) when value > 0,
    do: %Controller{type: :joystick, joystick: 1, direction: :right}

  def create_controller_event(%InputEvent{type: :AXIS_Y_1, value: value}) when value < 0,
    do: %Controller{type: :joystick, joystick: 1, direction: :up}

  def create_controller_event(%InputEvent{type: :AXIS_Y_1, value: value}) when value > 0,
    do: %Controller{type: :joystick, joystick: 1, direction: :down}

  def create_controller_event(%InputEvent{type: :AXIS_X_2, value: value}) when value < 0,
    do: %Controller{type: :joystick, joystick: 2, direction: :left}

  def create_controller_event(%InputEvent{type: :AXIS_X_2, value: value}) when value > 0,
    do: %Controller{type: :joystick, joystick: 2, direction: :right}

  def create_controller_event(%InputEvent{type: :AXIS_Y_2, value: value}) when value < 0,
    do: %Controller{type: :joystick, joystick: 2, direction: :up}

  def create_controller_event(%InputEvent{type: :AXIS_Y_2, value: value}) when value > 0,
    do: %Controller{type: :joystick, joystick: 2, direction: :down}

  # Center/neutral position for joysticks
  def create_controller_event(%InputEvent{type: axis_type, value: 0})
      when axis_type in [:AXIS_X_1, :AXIS_Y_1],
      do: %Controller{type: :joystick, joystick: 1, direction: :center}

  def create_controller_event(%InputEvent{type: axis_type, value: 0})
      when axis_type in [:AXIS_X_2, :AXIS_Y_2],
      do: %Controller{type: :joystick, joystick: 2, direction: :center}

  # Joystick button events
  def create_controller_event(%InputEvent{type: :BUTTON_A_1, value: value}),
    do: %Controller{type: :joystick, joystick: 1, joy_button: :a, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_A_2, value: value}),
    do: %Controller{type: :joystick, joystick: 2, joy_button: :a, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_B_1, value: value}),
    do: %Controller{type: :joystick, joystick: 1, joy_button: :b, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_B_2, value: value}),
    do: %Controller{type: :joystick, joystick: 2, joy_button: :b, action: value_to_action(value)}

  def create_controller_event(%InputEvent{type: :BUTTON_MENU, value: value}),
    do: %Controller{
      type: :joystick,
      joystick: 1,
      joy_button: :menu,
      action: value_to_action(value)
    }

  @doc """
  Creates a Proximity domain event from a protobuf ProximityEvent.

  Converts the protobuf format to a more Elixir-friendly structure with
  better field names and adds a timestamp.
  """
  def create_proximity_event(%ProximityEvent{
        panel_index: panel_index,
        sensor_index: sensor_index,
        distance_mm: distance_mm
      }) do
    %Proximity{
      panel: panel_index,
      sensor: sensor_index,
      distance_mm: distance_mm,
      timestamp: System.os_time(:millisecond)
    }
  end

  @doc """
  Creates an Audio domain event from a protobuf SoundToLightControlEvent.

  Converts the protobuf audio analysis data to a clean domain event with
  timestamp for audio-reactive lighting effects.
  """
  def create_audio_event(%SoundToLightControlEvent{bass: bass, mid: mid, high: high}) do
    %Audio{
      bass: bass,
      mid: mid,
      high: high,
      timestamp: System.os_time(:millisecond)
    }
  end

  # Helper function to convert protobuf values to semantic actions
  defp value_to_action(1), do: :press
  defp value_to_action(0), do: :release
end
