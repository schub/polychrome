defmodule Octopus.Apps.Snake.Game do
  alias Octopus.Font
  alias Octopus.Sprite

  defmodule Worm do
    @base_speed 20
    defstruct [:parts, :rem_t, :speed]

    def new() do
      %Worm{
        parts: [{{2, 5}, :r}, {{1, 5}, :r}, {{0, 5}, :r}],
        rem_t: @base_speed,
        speed: @base_speed
      }
    end

    defp move(parts, dir), do: move([], parts, dir)

    defp move(acc, [], _), do: Enum.reverse(acc)

    defp move(acc, [{{x, y}, pdir} | tail], dir) do
      newpos =
        case pdir do
          :u -> {x, y - 1}
          :d -> {x, y + 1}
          :l -> {x - 1, y}
          :r -> {x + 1, y}
        end

      move([{newpos, dir} | acc], tail, pdir)
    end

    def allowed_dirs(%Worm{parts: [_, {_, prev_dir} | _]} = _worm, dirs) do
      disallowed_dir =
        case prev_dir do
          :u -> :d
          :d -> :u
          :l -> :r
          :r -> :l
        end

      dirs
      |> Enum.reject(fn dir -> dir == disallowed_dir end)
    end

    def tick(worm, [dir | _]), do: tick(worm, dir)
    def tick(%Worm{parts: [{_, dir} | _]} = worm, []), do: tick(worm, dir)

    def tick(%Worm{rem_t: 0} = worm, dir) do
      %Worm{
        worm
        | parts: move(worm.parts, dir),
          rem_t: worm.speed
      }
    end

    def tick(%Worm{parts: [{pos, _} | parttail], rem_t: rem_t} = worm, dir),
      do: %Worm{worm | parts: [{pos, dir} | parttail], rem_t: rem_t - 1}

    def dead?(%Worm{parts: parts}) do
      parts
      |> Enum.reduce({MapSet.new(), false}, fn {{x, y} = p, _}, {acc, c} ->
        c = c or x < 0 or y < 0 or x >= 8 or y >= 8
        {MapSet.put(acc, p), MapSet.member?(acc, p) or c}
      end)
      |> elem(1)
    end

    def positions(%Worm{parts: parts}) do
      parts |> Enum.reduce([], fn {p, _}, acc -> [p | acc] end) |> Enum.reverse()
    end
  end

  defstruct [:worm, :food, :score, :layout, :moved]
  alias Octopus.Canvas
  alias Octopus.JoyState
  alias Octopus.Apps.Snake
  alias Snake.Game

  def new(args) do
    worm = Worm.new()

    title = Sprite.load("../images/snake", 0)

    %Game{
      worm: Worm.new(),
      food: new_food(worm),
      score: 0,
      moved: false,
      layout:
        case args[:layout] do
          nil ->
            if args[:side] != :right do
              %{
                base_canvas: Canvas.new(40, 8) |> Canvas.overlay(title),
                score_base: 16,
                playfield_base: 8 * 4,
                playfield_channel: 5
              }
            else
              %{
                base_canvas:
                  Canvas.new(40, 8)
                  |> Canvas.overlay(title, offset: {4 * 8, 0}),
                score_base: 16,
                playfield_base: 0,
                playfield_channel: 6
              }
            end

          layout when layout != nil ->
            layout
        end
    }
  end

  def new_food(%Worm{} = worm) do
    food = {:rand.uniform(8) - 1, :rand.uniform(8) - 1}

    cond do
      food in Worm.positions(worm) -> new_food(worm)
      true -> food
    end
  end

  def tick(%Game{food: food} = game, joy) do
    dirs = game.worm |> Worm.allowed_dirs(JoyState.direction(joy))
    moved = dirs != []
    new_worm = game.worm |> Worm.tick(dirs)

    new_game =
      case hd(new_worm.parts) do
        {^food, _} ->
          wormy = %Worm{new_worm | parts: [hd(new_worm.parts) | game.worm.parts]}

          Octopus.App.play_sample("snake/food_eaten.wav", game.layout.playfield_channel)

          %Game{
            game
            | worm: %Worm{wormy | speed: (wormy.speed - 1) |> Octopus.Util.clamp(10, 60)},
              food: new_food(wormy),
              score: game.score + 1
          }

        _ ->
          %Game{
            game
            | worm: new_worm,
              moved: game.moved || moved
          }
      end

    cond do
      Worm.dead?(new_game.worm) ->
        if new_game.moved do
          Octopus.App.play_sample("snake/death.wav", new_game.layout.playfield_channel)
        end

        Game.new(layout: new_game.layout)

      true ->
        new_game
    end
  end

  def render_canvas(%Game{layout: layout} = game) do
    gamecanvas =
      Canvas.new(8, 8)
      |> Canvas.put_pixel(game.food, {0xFF, 0xFF, 0x00})

    gamecanvas =
      game.worm.parts
      |> Enum.reduce(gamecanvas, fn {pos, _dir}, acc ->
        acc |> Canvas.put_pixel(pos, {0x10, 0xFF, 0x10})
      end)

    [first, second] =
      game.score |> to_string() |> String.pad_leading(2, "0") |> String.to_charlist()

    font = Font.load("gunb")
    font_variant = 8

    canvas =
      layout.base_canvas
      |> Canvas.overlay(gamecanvas, offset: {layout.playfield_base, 0})
      |> Font.pipe_draw_char(font, second, font_variant, {layout.score_base, 0})
      |> (fn c ->
            if first != ?0 do
              c |> Font.pipe_draw_char(font, first, font_variant, {layout.score_base - 8, 0})
            else
              c
            end
          end).()

    canvas
  end
end
