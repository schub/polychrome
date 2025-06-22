defmodule Octopus.Apps.InputTester do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.Frame
  alias Octopus.Events.Event.Controller, as: ControllerEvent

  defmodule State do
    defstruct [:position, :color, :palette]
  end

  def name(), do: "Input Tester"

  def app_init(_args) do
    state = %State{position: 0, color: 1, palette: ColorPalette.load("pico-8")}

    send(self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    render_frame(state)

    {:noreply, state}
  end

  def handle_input(%ControllerEvent{type: :button, action: :press, button: button}, state) do
    Logger.info("Button #{button} pressed")
    {:noreply, state}
  end

  def handle_input(%ControllerEvent{type: :button, action: :release, button: button}, state) do
    Logger.info("Button #{button} released")
    {:noreply, state}
  end

  # New joystick movement events
  def handle_input(
        %ControllerEvent{type: :joystick, joystick: joystick, direction: direction},
        state
      ) do
    Logger.info("Joystick #{joystick} moved #{direction}")
    {:noreply, state}
  end

  # New joystick button events
  def handle_input(
        %ControllerEvent{
          type: :joystick,
          joystick: joystick,
          joy_button: joy_button,
          action: action
        },
        state
      ) do
    Logger.info("Joystick #{joystick} button #{joy_button} #{action}")
    {:noreply, state}
  end

  # Catch-all for any other events
  def handle_input(%ControllerEvent{} = event, state) do
    Logger.info("Other input: #{inspect(event)}")
    {:noreply, state}
  end

  def handle_input(event, state) do
    Logger.info("Non-ControllerEvent: #{inspect(event)}")
    {:noreply, state}
  end

  defp render_frame(%State{} = state) do
    installation = Octopus.installation()
    num_buttons = installation.num_buttons()
    panel_size = installation.panel_size()

    # Use dynamic number of pixels based on installation
    total_pixels = panel_size * num_buttons

    data =
      List.duplicate(0, total_pixels)
      |> List.update_at(rem(state.position, total_pixels), fn _ -> state.color end)

    %Frame{
      data: data,
      palette: state.palette
    }
    |> send_frame()
  end
end
