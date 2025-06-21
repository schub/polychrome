defmodule Octopus.InputAdapter do
  use GenServer
  require Logger

  alias Octopus.Protobuf.SoundToLightControlEvent
  alias Octopus.{Protobuf, Events}
  alias Octopus.Protobuf.{InputEvent, InputLightEvent}
  alias Octopus.Events.Event.Controller, as: ControllerEvent

  @local_port 4423

  defmodule State do
    defstruct [:udp, :from_ip, :from_port]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_light_event(button, duration) when is_integer(button) and button >= 1 do
    max_buttons = Octopus.installation().num_buttons()

    if button <= max_buttons do
      binary =
        %InputLightEvent{
          type: "BUTTON_#{button}" |> String.to_existing_atom(),
          duration: duration
        }
        |> Protobuf.encode()

      GenServer.cast(__MODULE__, {:send_binary, binary})
    end
  end

  def init(:ok) do
    Logger.info("Starting input adapter. Listening on port #{@local_port}")
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true])

    {:ok, %State{udp: udp}}
  end

  def handle_cast({:send_binary, binary}, %State{udp: udp} = state) do
    if not is_nil(state.from_ip) do
      :gen_udp.send(udp, {state.from_ip, state.from_port}, binary)
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, from_port, packet}, state = %State{}) do
    case Protobuf.decode_packet(packet) do
      {:ok, %InputEvent{} = input_event} ->
        # Convert protobuf input event to internal format
        internal_event = convert_to_internal_format(input_event)
        # Logger.debug("#{__MODULE__}: Received input event: #{inspect(internal_event)}")
        Events.handle_event(internal_event)

      {:ok, %SoundToLightControlEvent{} = stl_event} ->
        # Logger.debug("#{__MODULE__}: Received stl event event: #{inspect(stl_event)}")
        Events.handle_event(stl_event)

      {:ok, content} ->
        Logger.warning("#{__MODULE__}: Received unexpected packet: #{inspect(content)}")

      {:error, error} ->
        Logger.warning("#{__MODULE__}: Error decoding packet #{inspect(error)}")
    end

    {:noreply, %State{state | from_ip: from_ip, from_port: from_port}}
  end

  # Convert protobuf InputEvent to internal format
  # Screen buttons: BUTTON_X -> %{type: :button, button: X, action: :press/:release}
  # Joystick events: Convert to new semantic format
  defp convert_to_internal_format(%InputEvent{type: button_type, value: value}) do
    case button_type do
      # Screen buttons - convert to new format
      :BUTTON_1 ->
        %ControllerEvent{type: :button, button: 1, action: value_to_action(value)}

      :BUTTON_2 ->
        %ControllerEvent{type: :button, button: 2, action: value_to_action(value)}

      :BUTTON_3 ->
        %ControllerEvent{type: :button, button: 3, action: value_to_action(value)}

      :BUTTON_4 ->
        %ControllerEvent{type: :button, button: 4, action: value_to_action(value)}

      :BUTTON_5 ->
        %ControllerEvent{type: :button, button: 5, action: value_to_action(value)}

      :BUTTON_6 ->
        %ControllerEvent{type: :button, button: 6, action: value_to_action(value)}

      :BUTTON_7 ->
        %ControllerEvent{type: :button, button: 7, action: value_to_action(value)}

      :BUTTON_8 ->
        %ControllerEvent{type: :button, button: 8, action: value_to_action(value)}

      :BUTTON_9 ->
        %ControllerEvent{type: :button, button: 9, action: value_to_action(value)}

      :BUTTON_10 ->
        %ControllerEvent{type: :button, button: 10, action: value_to_action(value)}

      :BUTTON_11 ->
        %ControllerEvent{type: :button, button: 11, action: value_to_action(value)}

      :BUTTON_12 ->
        %ControllerEvent{type: :button, button: 12, action: value_to_action(value)}

      # Joystick movement - convert to semantic directions
      :AXIS_X_1 ->
        %ControllerEvent{
          type: :joystick,
          joystick: 1,
          direction: axis_value_to_direction(:x, value)
        }

      :AXIS_Y_1 ->
        %ControllerEvent{
          type: :joystick,
          joystick: 1,
          direction: axis_value_to_direction(:y, value)
        }

      :AXIS_X_2 ->
        %ControllerEvent{
          type: :joystick,
          joystick: 2,
          direction: axis_value_to_direction(:x, value)
        }

      :AXIS_Y_2 ->
        %ControllerEvent{
          type: :joystick,
          joystick: 2,
          direction: axis_value_to_direction(:y, value)
        }

      # Joystick buttons - convert to semantic button events
      :BUTTON_A_1 ->
        %ControllerEvent{
          type: :joystick,
          joystick: 1,
          joy_button: :a,
          action: value_to_action(value)
        }

      :BUTTON_A_2 ->
        %ControllerEvent{
          type: :joystick,
          joystick: 2,
          joy_button: :a,
          action: value_to_action(value)
        }

      :BUTTON_MENU ->
        %ControllerEvent{
          type: :joystick,
          joystick: 1,
          joy_button: :menu,
          action: value_to_action(value)
        }
    end
  end

  defp value_to_action(1), do: :press
  defp value_to_action(0), do: :release

  # Convert axis values to semantic directions
  defp axis_value_to_direction(:x, -1), do: :left
  defp axis_value_to_direction(:x, 0), do: :center
  defp axis_value_to_direction(:x, 1), do: :right
  defp axis_value_to_direction(:y, -1), do: :up
  defp axis_value_to_direction(:y, 0), do: :center
  defp axis_value_to_direction(:y, 1), do: :down
end
