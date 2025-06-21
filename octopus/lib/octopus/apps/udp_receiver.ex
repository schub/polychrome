defmodule Octopus.Apps.UdpReceiver do
  use Octopus.App
  require Logger

  alias Octopus.Protobuf
  alias Octopus.Protobuf.{Frame, RGBFrame, WFrame, InputEvent}
  alias Octopus.Events.Event.Controller, as: ControllerEvent

  @supported_frames [Frame, WFrame, RGBFrame]

  @moduledoc """
  Will open a UDP port and listen for protobuf packets. All valid frames will be forwarded to the mixer.

  Any input events will be forwarded to the last IP address that sent a packet.
  """

  defmodule State do
    defstruct [:udp, :remote_ip, :remote_port]
  end

  @port 2342

  def name(), do: "UDP Receiver (Port: #{@port})"

  def app_init(_args) do
    Logger.info("#{__MODULE__}: Listening on UDP port #{inspect(@port)} for protobuf packets.")

    {:ok, udp} = :gen_udp.open(@port, [:binary, active: true, ip: bind_address()])

    state = %State{
      udp: udp
    }

    {:ok, state}
  end

  def handle_info({:udp, _socket, ip, port, protobuf}, state = %State{}) do
    case Protobuf.decode_packet(protobuf) do
      {:ok, %frame_type{} = frame} when frame_type in @supported_frames ->
        Logger.debug("#{__MODULE__}: Received #{frame_type} from #{inspect(ip)}:#{inspect(port)}")
        send_frame(frame)

      {:ok, %{} = unsupported} ->
        Logger.warning(
          "#{__MODULE__}: Received unsupported frame from #{inspect(ip)} #{inspect(unsupported)}"
        )

        :noop

      {:error, error} ->
        Logger.warning("#{__MODULE__}: Could not decode. #{inspect(error)} from #{inspect(ip)}")

        :noop
    end

    {:noreply, %State{state | remote_ip: ip, remote_port: port}}
  end

  def handle_input(%ControllerEvent{}, %State{remote_ip: nil} = state) do
    {:noreply, state}
  end

  def handle_input(%ControllerEvent{} = controller_event, %State{} = state) do
    # Convert ControllerEvent back to protobuf InputEvent for forwarding
    protobuf_event = convert_to_protobuf_format(controller_event)
    binary = Protobuf.encode(protobuf_event)
    :gen_udp.send(state.udp, state.remote_ip, state.remote_port, binary)
    {:noreply, state}
  end

  # Convert internal ControllerEvent back to protobuf InputEvent format
  defp convert_to_protobuf_format(%ControllerEvent{type: :button, button: button, action: action}) do
    button_type = String.to_existing_atom("BUTTON_#{button}")

    value =
      case action do
        :press -> 1
        :release -> 0
      end

    %InputEvent{type: button_type, value: value}
  end

  # Convert new joystick movement events back to protobuf format
  defp convert_to_protobuf_format(%ControllerEvent{
         type: :joystick,
         joystick: joystick,
         direction: direction
       })
       when direction != nil do
    {axis_type, value} = joystick_direction_to_protobuf(joystick, direction)
    %InputEvent{type: axis_type, value: value}
  end

  # Convert new joystick button events back to protobuf format
  defp convert_to_protobuf_format(%ControllerEvent{
         type: :joystick,
         joystick: joystick,
         joy_button: joy_button,
         action: action
       })
       when joy_button != nil do
    button_type = joystick_button_to_protobuf(joystick, joy_button)

    value =
      case action do
        :press -> 1
        :release -> 0
      end

    %InputEvent{type: button_type, value: value}
  end

  # Convert semantic joystick direction back to protobuf axis events
  defp joystick_direction_to_protobuf(joystick, direction) do
    {axis_x, axis_y} =
      case joystick do
        1 -> {:AXIS_X_1, :AXIS_Y_1}
        2 -> {:AXIS_X_2, :AXIS_Y_2}
      end

    case direction do
      :left -> {axis_x, -1}
      :right -> {axis_x, 1}
      :up -> {axis_y, -1}
      :down -> {axis_y, 1}
      # Use X axis for center
      :center -> {axis_x, 0}
    end
  end

  # Convert semantic joystick button back to protobuf button events
  defp joystick_button_to_protobuf(joystick, joy_button) do
    case {joystick, joy_button} do
      {1, :a} -> :BUTTON_A_1
      {2, :a} -> :BUTTON_A_2
      {1, :b} -> :BUTTON_B_1
      {2, :b} -> :BUTTON_B_2
      {_, :menu} -> :BUTTON_MENU
    end
  end

  def handle_control_event(event, state) do
    binary = Protobuf.encode(event)
    :gen_udp.send(state.udp, state.remote_ip, state.remote_port, binary)
    Logger.info("UDP: Control event received. #{inspect(event)}}")
    {:noreply, state}
  end

  # special case for fly.io
  defp bind_address() do
    case System.fetch_env("FLY_APP_NAME") do
      {:ok, _} ->
        {:ok, fly_global_ip} = :inet.getaddr(~c"fly-global-services", :inet)
        Logger.info("#{__MODULE__}: On fly.io, binding to #{inspect(fly_global_ip)}")
        fly_global_ip

      :error ->
        {0, 0, 0, 0}
    end
  end
end
