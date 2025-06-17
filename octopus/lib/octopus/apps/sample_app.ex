defmodule Octopus.Apps.SampleApp do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.Protobuf.InputEvent
  alias Octopus.VirtualMatrix

  defdelegate installation, to: Octopus

  defmodule State do
    defstruct [:index, :color, :canvas, :virtual_matrix]
  end

  @fps 60
  @colors [{255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {255, 0, 255}]

  def name(), do: "Sample App"

  def app_init(_args) do
    virtual_matrix = VirtualMatrix.new(installation(), layout: :gapped_panels)

    state = %State{
      index: 0,
      color: 0,
      canvas: Canvas.new(virtual_matrix.width, virtual_matrix.height),
      virtual_matrix: virtual_matrix
    }

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

    VirtualMatrix.send_frame(state.virtual_matrix, canvas)

    {:noreply,
     %State{
       state
       | canvas: canvas,
         index: rem(state.index + 1, state.virtual_matrix.width * state.virtual_matrix.height)
     }}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, %State{state | color: min(length(@colors) - 1, state.color + 1)}}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    {:noreply, %State{state | color: max(0, state.color - 1)}}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
