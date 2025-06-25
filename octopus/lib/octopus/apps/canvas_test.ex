defmodule Octopus.Apps.CanvasTest do
  alias Octopus.Canvas
  use Octopus.App, category: :test

  @tick_interval 50

  def name(), do: "Canvas Test"

  def app_init(_args) do
    # Configure display using new unified API - gapped layout (was Canvas.to_frame(drop: true))
    Octopus.App.configure_display(layout: :gapped_panels)

    :timer.send_interval(@tick_interval, self(), :tick)

    canvas =
      Canvas.new(80 + 9 * 18, 8)
      |> Canvas.polygon(
        [
          {2, 0},
          {5, 0},
          {7, 2},
          {7, 5},
          {5, 7},
          {2, 7},
          {0, 5},
          {0, 2}
        ],
        {255, 0, 0}
      )

    {:ok, %{canvas: canvas}}
  end

  def handle_info(:tick, %{canvas: canvas} = state) do
    canvas = canvas |> Canvas.translate({1, 0}, :wrap)
    Octopus.App.update_display(canvas)
    {:noreply, %{state | canvas: canvas}}
  end
end
