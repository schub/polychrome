defmodule Octopus.Apps.SampleApp do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.VirtualMatrix
  alias Octopus.Canvas

  defdelegate installation, to: Octopus

  defmodule State do
    defstruct [:index, :color, :canvas, :virtual_matrix, :palette]
  end

  @fps 60

  def name(), do: "Sample"

  def app_init(_args) do
    virtual_matrix = VirtualMatrix.new(installation(), layout: :gapped_panels)
    canvas = Canvas.new(virtual_matrix.width, virtual_matrix.height)

    state = %State{
      index: 0,
      canvas: canvas,
      virtual_matrix: virtual_matrix
    }

    VirtualMatrix.send_frame(state.virtual_matrix, canvas)

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    coordinates =
      {rem(state.index, state.virtual_matrix.width),
       trunc(state.index / state.virtual_matrix.width)}

    hue_step = 359.0 / (state.virtual_matrix.width * state.virtual_matrix.height)
    hue = hue_step * state.index

    %Chameleon.RGB{r: r, g: g, b: b} =
      hue
      |> Chameleon.HSL.new(100, 50)
      |> Chameleon.convert(Chameleon.RGB)

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.put_pixel(coordinates, {r, g, b})

    VirtualMatrix.send_frame(state.virtual_matrix, canvas)

    {:noreply,
     %State{
       state
       | canvas: canvas,
         index: rem(state.index + 1, state.virtual_matrix.width * state.virtual_matrix.height)
     }}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, state) do
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

  def handle_event(%InputEvent{type: :button, action: :press, button: 2}, state) do
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

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
