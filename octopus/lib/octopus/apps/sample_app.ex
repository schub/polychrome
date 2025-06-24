defmodule Octopus.Apps.SampleApp do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Canvas, ColorPalette}
  alias Octopus.Events.Event.Controller, as: ControllerEvent

  defmodule State do
    defstruct [:index, :color, :canvas, :display_info, :palette]
  end

  @fps 60
  @colors [{255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {255, 0, 255}]

  def name(), do: "Sample"

  def app_init(_args) do
    # Configure display using new unified API - gapped layout (was VirtualMatrix :gapped_panels)
    Octopus.App.configure_display(layout: :gapped_panels)

    # Get display info instead of VirtualMatrix
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)
    palette = ColorPalette.load("pico-8")

    state = %State{
      index: 0,
      color: 7,
      canvas: canvas,
      display_info: display_info,
      palette: palette
    }

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    coordinates =
      {rem(state.index, state.display_info.width), trunc(state.index / state.display_info.width)}

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.put_pixel(coordinates, Enum.at(@colors, state.color))

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    {:noreply,
     %State{
       state
       | canvas: canvas,
         index: rem(state.index + 1, state.display_info.width * state.display_info.height)
     }}
  end

  def handle_input(%ControllerEvent{type: :button, action: :press, button: 1}, state) do
    state = %State{state | color: 8}

    canvas =
      state.canvas
      |> Canvas.fill_rect(
        {0, 0},
        {state.display_info.width - 1, state.display_info.height - 1},
        state.color
      )

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(%ControllerEvent{type: :button, action: :press, button: 2}, state) do
    state = %State{state | color: 7}

    canvas =
      state.canvas
      |> Canvas.fill_rect(
        {0, 0},
        {state.display_info.width - 1, state.display_info.height - 1},
        state.color
      )

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(%ControllerEvent{}, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
