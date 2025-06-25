defmodule Octopus.InputAdapter do
  use GenServer
  require Logger

  alias Octopus.{Protobuf, Events}
  alias Octopus.Protobuf.{InputEvent, InputLightEvent, SoundToLightControlEvent}
  alias Octopus.Events.Factory

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
    # Configuration is centralized in config.exs
    local_port = Application.fetch_env!(:octopus, :controller_interface_port)
    Logger.info("Starting input adapter. Listening on port #{local_port}")
    {:ok, udp} = :gen_udp.open(local_port, [:binary, active: true])

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
        # Convert protobuf input event to domain event
        domain_event = Factory.create_input_event(input_event)
        # Logger.debug("#{__MODULE__}: Received input event: #{inspect(domain_event)}")
        Events.handle_event(domain_event)

      {:ok, %SoundToLightControlEvent{} = stl_event} ->
        domain_event = Factory.create_audio_event(stl_event)
        # Logger.debug("#{__MODULE__}: Received audio event: #{inspect(domain_event)}")
        Events.handle_event(domain_event)

      {:ok, content} ->
        Logger.warning("#{__MODULE__}: Received unexpected packet: #{inspect(content)}")

      {:error, error} ->
        Logger.warning("#{__MODULE__}: Error decoding packet #{inspect(error)}")
    end

    {:noreply, %State{state | from_ip: from_ip, from_port: from_port}}
  end
end
