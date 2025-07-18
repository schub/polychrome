defmodule Octopus.Apps.SpaceInvaders do
  use Octopus.App, category: :game

  alias Octopus.Canvas
  alias Octopus.Protobuf.AudioFrame
  alias Octopus.Events.Event.Input, as: InputEvent

  require Logger

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule Game do
    defstruct [:invaders, :dirs, :bullets, :player, :staggered_tick, :invader_tick, :moves]

    def new() do
      %Game{
        invaders: [
          %{x: 5, y: 2, moves: []},
          %{x: 3, y: 2, moves: []},
          %{x: 1, y: 2, moves: []},
          %{x: 4, y: 1, moves: []},
          %{x: 2, y: 1, moves: []},
          %{x: 5, y: 0, moves: []},
          %{x: 3, y: 0, moves: []},
          %{x: 1, y: 0, moves: []}
        ],
        moves:
          [
            %{x: 1, y: 0},
            %{x: 1, y: 0},
            %{x: 0, y: 1},
            %{x: -1, y: 0},
            %{x: -1, y: 0},
            %{x: -1, y: 0},
            %{x: 0, y: 1},
            %{x: 1, y: 0}
          ]
          |> Stream.cycle(),
        staggered_tick: 0.0,
        invader_tick: 0.0,
        bullets: [],
        player: %{x: 4, y: 7, shoot_anim: 0},
        dirs: Stream.cycle([%{x: 1, y: 0}, %{x: 0, y: 1}, %{x: -1, y: 0}])
      }
    end

    def draw(%Game{} = game, %Canvas{} = canvas, {offset_x, offset_y}) do
      canvas =
        Enum.reduce(game.bullets ++ game.invaders, canvas, fn %{x: x, y: y}, canvas ->
          Canvas.put_pixel(canvas, {offset_x + trunc(x), offset_y + trunc(y)}, {255, 255, 255})
        end)

      player_color = {0, 255, 0}

      player_gun_color =
        if rem(trunc(ceil(game.player.shoot_anim)), 2) == 0, do: player_color, else: {0, 0, 0}

      canvas =
        [
          {{game.player.x - 1, game.player.y}, player_color},
          {{game.player.x + 1, game.player.y}, player_color},
          {{game.player.x, game.player.y}, player_color},
          {{game.player.x, game.player.y - 1}, player_gun_color}
        ]
        |> Enum.filter(fn {{x, _y}, _color} -> x >= 0 and x < 8 end)
        |> Enum.reduce(canvas, fn {{x, y}, color}, canvas ->
          Canvas.put_pixel(canvas, {offset_x + x, offset_y + y}, color)
        end)

      canvas
    end

    def update_player(%Game{} = game, dt) do
      player = Map.update(game.player, :shoot_anim, 0, &max(0, &1 - dt * 20))
      %Game{game | player: player}
    end

    def update_bullets(%Game{} = game, dt) do
      bullets =
        Enum.reduce(game.bullets, [], fn %{x: x, y: y}, bullets ->
          if y > 0 do
            [%{x: x, y: y - 12 * dt} | bullets]
          else
            bullets
          end
        end)

      %Game{game | bullets: bullets}
    end

    def kill_invaders(%Game{} = game) do
      {dead_invaders, invaders} =
        Enum.split_with(game.invaders, fn %{x: x, y: y} ->
          game.bullets |> Enum.any?(fn %{x: bx, y: by} -> trunc(bx) == x and trunc(by) == y end)
        end)

      bullets =
        Enum.reject(game.bullets, fn %{x: x, y: y} ->
          Enum.any?(dead_invaders, fn %{x: dx, y: dy} -> trunc(x) == dx and trunc(y) == dy end)
        end)

      if length(dead_invaders) > 0 do
        send_frame(%AudioFrame{uri: "file://space-invader/invaderkilled.wav", channel: 5})
      end

      %Game{game | invaders: invaders, bullets: bullets}
    end

    def global_movement(%Game{} = game, dt) do
      invader_tick = game.invader_tick + dt
      current_move = Enum.at(game.moves, 0)

      if invader_tick > 1.0 do
        invaders =
          Enum.map(game.invaders, fn %{moves: moves} = invader ->
            %{invader | moves: moves ++ [current_move]}
          end)

        %Game{
          game
          | invaders: invaders,
            invader_tick: 1.0 - invader_tick,
            moves: Stream.drop(game.moves, 1)
        }
      else
        %Game{game | invader_tick: invader_tick}
      end
    end

    def update(%Game{} = game, dt) do
      game
      |> Game.update_player(dt)
      |> Game.update_bullets(dt)
      |> Game.kill_invaders()
      |> Game.staggered_movement(dt)
      |> Game.global_movement(dt)
    end

    def staggered_movement(%Game{invaders: invaders, staggered_tick: tick} = game, dt) do
      staggered_tick = tick + dt

      if staggered_tick > 0.05 do
        invaders =
          update_first(
            invaders,
            fn %{moves: moves} -> length(moves) > 0 end,
            fn %{
                 x: x,
                 y: y,
                 moves: [move | moves]
               } = invader ->
              %{invader | x: x + move.x, y: y + move.y, moves: moves}
            end
          )

        %Game{game | invaders: invaders, staggered_tick: 0.05 - staggered_tick}
      else
        %Game{game | invaders: invaders, staggered_tick: staggered_tick}
      end
    end

    def move_left(%Game{player: %{x: x} = player} = game) do
      %Game{game | player: %{player | x: max(0, x - 1)}}
    end

    def move_right(%Game{player: %{x: x} = player} = game) do
      %Game{game | player: %{player | x: min(7, x + 1)}}
    end

    def shoot(%Game{player: %{x: x, y: y} = player} = game) do
      send_frame(%AudioFrame{uri: "file://space-invader/shoot.wav", channel: 5})

      player = %{player | shoot_anim: 2}
      %Game{game | player: player, bullets: [%{x: x, y: y - 1} | game.bullets]}
    end

    defp update_first(list, match_fun, update_fun) do
      update_first(list, match_fun, update_fun, [])
    end

    defp update_first([], _match_fun, _update_fun, acc), do: Enum.reverse(acc)

    defp update_first([head | tail], match_fun, update_fun, acc) do
      if match_fun.(head) do
        Enum.reverse(acc) ++ [update_fun.(head) | tail]
      else
        update_first(tail, match_fun, update_fun, [head | acc])
      end
    end
  end

  def name, do: "Space Invaders"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    installation_info.num_joysticks >= 1 and
      installation_info.panel_width == 8 and
      installation_info.panel_height == 8
  end

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    game = Game.new()
    canvas = Canvas.new(80, 8)
    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, %{game: game, canvas: canvas}}
  end

  def handle_info(:tick, %{game: game, canvas: canvas} = state) do
    game = Game.update(game, 1.0 / @frame_rate)
    canvas = Canvas.clear(canvas)
    canvas = Game.draw(game, canvas, {8 * 4, 0})
    Octopus.App.update_display(canvas)
    {:noreply, %{state | game: game, canvas: canvas}}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 10}, state) do
    {:noreply, %{state | game: Game.new()}}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :left},
        %{game: game} = state
      ) do
    {:noreply, %{state | game: Game.move_left(game)}}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :right},
        %{game: game} = state
      ) do
    {:noreply, %{state | game: Game.move_right(game)}}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: 5},
        %{game: game} = state
      ) do
    {:noreply, %{state | game: Game.shoot(game)}}
  end

  def handle_event(_, state) do
    {:noreply, state}
  end
end
