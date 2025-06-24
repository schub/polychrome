defmodule Octopus.ButtonState do
  defstruct [:buttons, :joy1, :joy2]

  alias Octopus.JoyState
  alias Octopus.ButtonState
  alias Octopus.Events.Event.Input, as: InputEvent

  defp button_map() do
    num_buttons = Octopus.installation().num_buttons()

    1..num_buttons
    |> Enum.map(fn i -> {i, i - 1} end)
    |> Enum.into(%{})
  end

  def new() do
    %ButtonState{
      buttons: MapSet.new(),
      joy1: JoyState.new(),
      joy2: JoyState.new()
    }
  end

  def press(%ButtonState{buttons: buttons} = bs, button) do
    %ButtonState{bs | buttons: buttons |> MapSet.put(button)}
  end

  def release(%ButtonState{buttons: buttons} = bs, button) do
    %ButtonState{bs | buttons: buttons |> MapSet.delete(button)}
  end

  def handle_event(%ButtonState{} = bs, %InputEvent{
        type: :button,
        button: button_num,
        action: action
      }) do
    case action do
      :press -> bs |> press({:sb, button_to_index(button_num)}) |> press(button_num)
      :release -> bs |> release({:sb, button_to_index(button_num)}) |> release(button_num)
    end
  end

  # Handle joystick direction events and convert to axis events for JoyState compatibility
  def handle_event(%ButtonState{} = bs, %InputEvent{
        type: :joystick,
        joystick: joystick,
        direction: direction
      })
      when direction != nil do
    # Convert semantic direction back to axis events for JoyState compatibility
    joy_state_key = if joystick == 1, do: :joy1, else: :joy2
    current_joy = Map.get(bs, joy_state_key)

    # Convert direction to axis events for JoyState compatibility
    {axis_type, value} = direction_to_axis_event(joystick, direction)
    updated_joy = JoyState.handle_event(current_joy, axis_type, value)

    Map.put(bs, joy_state_key, updated_joy)
  end

  def handle_event(%ButtonState{} = bs, %InputEvent{
        type: :joystick,
        joystick: joystick,
        joy_button: joy_button,
        action: action
      })
      when joy_button != nil do
    # Convert semantic joy_button back to button events for JoyState compatibility
    joy_state_key = if joystick == 1, do: :joy1, else: :joy2
    current_joy = Map.get(bs, joy_state_key)

    # Convert joy_button to button events for JoyState compatibility
    {button_type, value} = joy_button_to_button_event(joystick, joy_button, action)
    updated_joy = JoyState.handle_event(current_joy, button_type, value)

    Map.put(bs, joy_state_key, updated_joy)
  end

  def button_to_index(button_num) when is_integer(button_num) do
    Map.get(button_map(), button_num, nil)
  end

  def index_to_button(index) do
    index + 1
  end

  def screen_button?(%ButtonState{buttons: buttons}, index),
    do: MapSet.member?(buttons, index_to_button(index))

  def button?(%ButtonState{buttons: buttons}, button),
    do: MapSet.member?(buttons, button)

  # Convert semantic direction back to axis events for JoyState compatibility
  defp direction_to_axis_event(joystick, direction) do
    axis_x = if joystick == 1, do: :AXIS_X_1, else: :AXIS_X_2
    axis_y = if joystick == 1, do: :AXIS_Y_1, else: :AXIS_Y_2

    case direction do
      :left -> {axis_x, -1}
      :right -> {axis_x, 1}
      :up -> {axis_y, -1}
      :down -> {axis_y, 1}
      # Use X axis for center, will clear both directions
      :center -> {axis_x, 0}
    end
  end

  # Convert semantic joy_button back to button events for JoyState compatibility
  defp joy_button_to_button_event(joystick, joy_button, action) do
    button_type =
      case {joystick, joy_button} do
        {1, :a} -> :BUTTON_A_1
        {2, :a} -> :BUTTON_A_2
        {1, :b} -> :BUTTON_B_1
        {2, :b} -> :BUTTON_B_2
        # Menu button doesn't have joystick variants
        {_, :menu} -> :BUTTON_MENU
      end

    value =
      case action do
        :press -> 1
        :release -> 0
      end

    {button_type, value}
  end
end
