defmodule Octopus.Transitions do
  alias Octopus.Canvas

  @moduledoc """
  Implements transitions between two canvases.

  Returns a stream of canvases.
  """

  def flipdot(%Canvas{} = canvas1, %Canvas{} = canvas2) do
    coordinates = for y <- 0..(canvas2.height - 1), x <- 0..(canvas2.width - 1), do: {x, y}

    Stream.transform(
      coordinates,
      canvas1,
      fn coordinate, canvas ->
        pixel = Canvas.get_pixel(canvas2, coordinate)
        canvas = Canvas.put_pixel(canvas, coordinate, pixel)
        {[canvas], canvas}
      end
    )
  end

  @doc """
  Canvas2 pushes canvas1 out to one side.
  Returns a stream of canvases that are intended to be played at constant frame rate.

  ## Options
  * `:direction` - `:left`, `:right`, `:top`, or `:bottom` [default: `:left`]
  * `:separation` - number of separation pixels between the two canvases [default: 3]

  """

  def push(%Canvas{} = canvas1, %Canvas{} = canvas2, opts \\ []) do
    direction = Keyword.get(opts, :direction, :left)
    separation = Keyword.get(opts, :separation, 3)

    joined =
      case direction do
        :left ->
          canvas1
          |> Canvas.join(Canvas.new(separation, canvas1.height), direction: :horizontal)
          |> Canvas.join(canvas2, direction: :horizontal)

        :right ->
          canvas2
          |> Canvas.join(Canvas.new(separation, canvas2.height), direction: :horizontal)
          |> Canvas.join(canvas1, direction: :horizontal)

        :top ->
          canvas1
          |> Canvas.join(Canvas.new(canvas1.width, separation), direction: :vertical)
          |> Canvas.join(canvas2, direction: :vertical)

        :bottom ->
          canvas2
          |> Canvas.join(Canvas.new(canvas2.width, separation), direction: :vertical)
          |> Canvas.join(canvas1, direction: :vertical)
      end

    cuts =
      case direction do
        :left ->
          0..(canvas1.width + separation)
          |> Enum.map(fn x -> {{x, 0}, {x + canvas1.width - 1, joined.height - 1}} end)

        :right ->
          (canvas1.width + separation)..0//-1
          |> Enum.map(fn x -> {{x, 0}, {x + canvas1.width - 1, joined.height - 1}} end)

        :top ->
          0..(canvas1.height + separation)
          |> Enum.map(fn y -> {{0, y}, {joined.width - 1, y + canvas1.height - 1}} end)

        :bottom ->
          (canvas1.height + separation)..0//-1
          |> Enum.map(fn y -> {{0, y}, {joined.width - 1, y + canvas1.height - 1}} end)
      end

    cuts
    |> Stream.map(fn {cut_start, cut_end} ->
      Canvas.cut(joined, cut_start, cut_end)
    end)
  end

  @doc """
  Canvas2 slides over canvas1. It uses easings for a smooth transtion.

  ## Options
  * `:direction` - `:left`, `:right`, `:top`, or `:bottom` [default: `:left`]
  """

  def slide_over(%Canvas{} = canvas1, %Canvas{} = canvas2, opts \\ []) do
    direction = Keyword.get(opts, :direction, :left)

    steps =
      1..7
      |> Enum.map(fn slide_distance ->
        case direction do
          :left ->
            left_canvas =
              Canvas.cut(
                canvas2,
                {canvas2.width - slide_distance, 0},
                {canvas2.width - 1, canvas2.height - 1}
              )

            right_canvas =
              Canvas.cut(canvas1, {slide_distance, 0}, {canvas1.width - 1, canvas1.height - 1})

            Canvas.join(left_canvas, right_canvas, direction: :horizontal)

          :right ->
            left_canvas =
              Canvas.cut(
                canvas1,
                {0, 0},
                {canvas1.width - slide_distance - 1, canvas1.height - 1}
              )

            right_canvas =
              Canvas.cut(canvas2, {0, 0}, {slide_distance - 1, canvas1.height - 1})

            Canvas.join(left_canvas, right_canvas, direction: :horizontal)

          :top ->
            top_canvas =
              Canvas.cut(
                canvas2,
                {0, canvas2.height - slide_distance},
                {canvas2.width - 1, canvas2.height - 1}
              )

            bottom_canvas =
              Canvas.cut(canvas1, {0, slide_distance}, {canvas1.width - 1, canvas1.height - 1})

            Canvas.join(top_canvas, bottom_canvas, direction: :vertical)

          :bottom ->
            top_canvas =
              Canvas.cut(
                canvas1,
                {0, 0},
                {canvas1.width - 1, canvas1.height - slide_distance - 1}
              )

            bottom_canvas =
              Canvas.cut(canvas2, {0, 0}, {canvas1.width - 1, slide_distance - 1})

            Canvas.join(top_canvas, bottom_canvas, direction: :vertical)
        end
      end)

    steps ++ [canvas2]
  end
end
