defmodule Octopus.Apps.SampleApp do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Canvas, ColorPalette}
  alias Octopus.Events.Event.Controller, as: ControllerEvent
  alias Octopus.VirtualMatrix

  defdelegate installation, to: Octopus

  defmodule State do
    defstruct [:index, :color, :canvas, :virtual_matrix, :palette]
  end

  @fps 60
  @colors [{255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {255, 0, 255}]

  def name(), do: "Sample"

  def app_init(_args) do
    virtual_matrix = VirtualMatrix.new(installation(), layout: :gapped_panels)
    canvas = Canvas.new(virtual_matrix.width, virtual_matrix.height)
    palette = ColorPalette.load("pico-8")

    state = %State{
      index: 0,
      color: 7,
      canvas: canvas,
      virtual_matrix: virtual_matrix,
      palette: palette
    }

    canvas
    |> Canvas.to_frame(palette)
    |> VirtualMatrix.send_frame(state.virtual_matrix)

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    coordinates =
      {rem(state.index, state.virtual_matrix.width),
       trunc(state.index / state.virtual_matrix.width)}

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.put_pixel(coordinates, Enum.at(@colors, state.color))

    canvas
    |> Canvas.to_frame(state.palette)
    |> VirtualMatrix.send_frame(state.virtual_matrix)

    {:noreply,
     %State{
       state
       | canvas: canvas,
         index: rem(state.index + 1, state.virtual_matrix.width * state.virtual_matrix.height)
     }}
  end

  def handle_input(%ControllerEvent{type: :button, action: :press, button: 1}, state) do
    state = %State{state | color: 8}

    state.canvas
    |> Canvas.fill_rect(
      {0, 0},
      {state.virtual_matrix.width - 1, state.virtual_matrix.height - 1},
      state.color
    )
    |> Canvas.to_frame(state.palette)
    |> VirtualMatrix.send_frame(state.virtual_matrix)

    {:noreply, state}
  end

  def handle_input(%ControllerEvent{type: :button, action: :press, button: 2}, state) do
    state = %State{state | color: 7}

    state.canvas
    |> Canvas.fill_rect(
      {0, 0},
      {state.virtual_matrix.width - 1, state.virtual_matrix.height - 1},
      state.color
    )
    |> Canvas.to_frame(state.palette)
    |> VirtualMatrix.send_frame(state.virtual_matrix)

    {:noreply, state}
  end

  def handle_input(%ControllerEvent{}, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
