defmodule Octopus.Apps.Whackamole.Game do
  use Octopus.Params, prefix: :whackamole
  require Logger
  alias Octopus.{Canvas, Font, Animator, Transitions, Sprite, InputAdapter}
  alias Octopus.Apps.Whackamole.Mole

  defstruct [
    :state,
    :score,
    :font,
    :lives,
    :moles,
    :difficulty,
    :whack_times,
    :highscore,
    :display_info,
    :panel_count,
    :panel_width,
    :panel_height,
    :active_animators,
    :panel_canvases,
    :display_canvas,
    :last_mole_spawn_time
  ]

  # game_states [:intro, :playing, :game_over, :tilt]

  @font_name "cshk-Captain Sky Hawk (RARE)"
  @sprite_sheet "256-characters-original"
  @highscore_file "whackamole_highscore"
  # 56..59
  @mole_sprites 0..255

  def new(display_info) do
    %__MODULE__{
      state: :intro,
      lives: 3,
      font: Font.load(@font_name),
      score: 0,
      difficulty: 1,
      moles: %{},
      whack_times: [],
      highscore: read_highscore(),
      display_info: display_info,
      panel_count: display_info.panel_count,
      panel_width: display_info.panel_width,
      panel_height: display_info.panel_height,
      active_animators: %{},
      panel_canvases: %{},
      display_canvas: Canvas.new(display_info.width, display_info.height),
      last_mole_spawn_time: System.os_time(:millisecond)
    }
  end

  def start_intro(game, app_pid) do
    # Start the intro sequence
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    whack =
      Canvas.new(6 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, " WHACK", game.font, 0)

    Logger.info("Starting intro WHACK animation")

    # Start "WHACK" animation
    Animator.animate(
      animation_id: {:intro_whack},
      app_pid: app_pid,
      canvas: whack,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {6 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule "'EM!" animation to start after "WHACK" completes
    :timer.send_after(duration + 100, {:start_intro_em})

    %{game | state: :intro}
  end

  def start_playing(game) do
    # Clear display and start playing
    blank_canvas = Canvas.new(game.display_info.width, game.display_info.height)
    send(self(), {:clear_display, blank_canvas})

    # Start mole spawning
    schedule_next_mole_spawn(game)

    %{game | state: :playing, active_animators: %{}, display_canvas: blank_canvas}
  end

  def start_game_over(game) do
    # Clear any remaining animators and start game over sequence
    clear_all_animators(game)
    start_game_over_animation(game)

    %{game | state: :game_over}
  end

  def start_tilt(game) do
    # Start tilt animation
    duration = 1000

    tilt =
      Canvas.new(10 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, "   TILT!", game.font, 3)

    blank_canvas =
      Canvas.new(10 * game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})

    transition_fun = &[&1, tilt, blank_canvas, tilt, blank_canvas, &2]

    Animator.animate(
      animation_id: {:tilt},
      app_pid: self(),
      canvas: tilt,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {10 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule end of tilt
    :timer.send_after(duration + 100, {:end_tilt})

    %{game | state: :tilt}
  end

  def end_tilt(game) do
    # Clear tilt animation and return to playing
    clear_all_animators(game)
    blank_canvas = Canvas.new(game.display_info.width, game.display_info.height)
    send(self(), {:clear_display, blank_canvas})

    # Resume mole spawning
    schedule_next_mole_spawn(game)

    %{game | state: :playing, active_animators: %{}, display_canvas: blank_canvas}
  end

  def handle_whack(game, button_number) do
    case game.state do
      :playing ->
        if Map.has_key?(game.moles, button_number) do
          # Successful whack
          moles = Map.delete(game.moles, button_number)
          score = game.score + 1

          # Clear the spawn animator for this panel
          spawn_animator_key = {:mole_spawn, button_number}

          updated_active_animators =
            if Map.has_key?(game.active_animators, spawn_animator_key) do
              Animator.clear(spawn_animator_key)
              send(self(), {:clear_panel_canvas, button_number})
              Map.delete(game.active_animators, spawn_animator_key)
            else
              game.active_animators
            end

          # Start success animation
          whack_success_animation(game, button_number)

          %{game | moles: moles, score: score, active_animators: updated_active_animators}
        else
          # Missed whack - check for tilt
          whack_fail_animation(game, button_number, false)
          now = System.os_time(:millisecond)
          whack_times = [now | game.whack_times]

          updated_game = %{game | whack_times: whack_times}
          check_tilt(updated_game)
        end

      _ ->
        # Ignore whacks in other states
        game
    end
  end

  def handle_mole_timeout(game, panel) do
    case game.state do
      :playing ->
        if Map.has_key?(game.moles, panel) do
          # Mole timed out
          moles = Map.delete(game.moles, panel)
          lives = game.lives - 1

          # Clear spawn animator
          spawn_animator_key = {:mole_spawn, panel}

          updated_active_animators =
            if Map.has_key?(game.active_animators, spawn_animator_key) do
              Animator.clear(spawn_animator_key)
              send(self(), {:clear_panel_canvas, panel})
              Map.delete(game.active_animators, spawn_animator_key)
            else
              game.active_animators
            end

          # Start lost animation
          mole = game.moles[panel]
          lost_animation(game, mole)

          updated_game = %{
            game
            | moles: moles,
              lives: lives,
              active_animators: updated_active_animators
          }

          # Check if game over
          if lives <= 0 do
            # Delay game over to allow animation to complete
            :timer.send_after(500, {:game_over})
            updated_game
          else
            updated_game
          end
        else
          game
        end

      _ ->
        game
    end
  end

  def maybe_spawn_mole(game) do
    case game.state do
      :playing ->
        now = System.os_time(:millisecond)
        mole_delay_ms = get_mole_delay_ms(game.difficulty)

        if now - game.last_mole_spawn_time > mole_delay_ms do
          panels_with_moles = Map.keys(game.moles)
          free_panels = Enum.to_list(0..(game.panel_count - 1)) -- panels_with_moles

          case free_panels do
            [] ->
              Logger.debug("No free panels for mole spawn")
              game

            _ ->
              panel = Enum.random(free_panels)
              mole = Mole.new(panel, now)
              moles = Map.put(game.moles, panel, mole)

              # Start spawn animation
              spawn_animation(game, panel)

              # Schedule mole timeout
              mole_timeout_ms = get_mole_timeout_ms(game.difficulty)
              :timer.send_after(mole_timeout_ms, {:mole_timeout, panel})

              %{game | moles: moles, last_mole_spawn_time: now}
          end
        else
          game
        end

      _ ->
        game
    end
  end

  def schedule_next_mole_spawn(game) do
    delay_ms = get_mole_spawn_interval_ms(game.difficulty)
    :timer.send_after(delay_ms, {:spawn_mole})
    :ok
  end

  def start_down_animation(game, panel) do
    # Start the down animation for a specific panel
    down_animation(game, panel)
    :ok
  end

  defp check_tilt(game) do
    tilt_duration_ms = param(:tilt_duration_ms, 1000)
    tilt_max = param(:tilt_max, 6)
    now = System.os_time(:millisecond)

    {_expired, active} =
      Enum.split_with(game.whack_times, fn time ->
        now - time > tilt_duration_ms
      end)

    case Enum.count(active) do
      count when count > tilt_max ->
        # Start tilt
        lives = game.lives - 1
        updated_game = %{game | lives: lives, whack_times: []}

        if lives <= 0 do
          # Game over after tilt
          :timer.send_after(1100, {:game_over})
          updated_game
        else
          send(self(), {:start_tilt})
          updated_game
        end

      _ ->
        %{game | whack_times: active}
    end
  end

  defp get_mole_delay_ms(difficulty) do
    base_delay = param(:mole_delay_s, 1.5) * 1000
    round(base_delay * difficulty)
  end

  defp get_mole_timeout_ms(difficulty) do
    base_timeout = param(:mole_time_to_live_s, 7) * 1000
    round(base_timeout * difficulty)
  end

  defp get_mole_spawn_interval_ms(difficulty) do
    # How often to check for spawning new moles
    base_interval = 500
    round(base_interval * difficulty)
  end

  defp spawn_animation(game, panel) do
    show_hints_till = 50
    current_time = System.os_time(:millisecond)

    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    mole_spawn_duration_ms = param(:mole_spawn_duration_ms, 300) * game.difficulty

    # Show light hint for early game
    if current_time - game.last_mole_spawn_time < show_hints_till * 1000 do
      InputAdapter.send_light_event(panel + 1, 1000)
    end

    Animator.animate(
      animation_id: {:mole_spawn, panel},
      app_pid: self(),
      canvas: sprite_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: mole_spawn_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    :ok
  end

  defp lost_animation(game, mole) do
    red_canvas = background_canvas(game, 0, 100, 100)
    blank_canvas = Canvas.new(game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})

    transition_fn = fn canvas_sprite, _ ->
      blended = Canvas.blend(canvas_sprite, red_canvas, :multiply, 1.0)
      [canvas_sprite, blended, canvas_sprite, blended, canvas_sprite, blended, blank_canvas]
    end

    lost_animation_duration_ms = param(:lost_animation_duration_ms, 500)

    Animator.animate(
      animation_id: {:mole_lost, mole.pannel},
      app_pid: self(),
      canvas: blank_canvas,
      position: {0, 0},
      transition_fun: transition_fn,
      duration: lost_animation_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )
  end

  defp down_animation(game, panel) do
    blank_canvas = Canvas.new(game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})
    green_canvas = background_canvas(game, 120, 100, 100)

    transition_fun = fn canvas_sprite, target ->
      blended = Canvas.blend(canvas_sprite, green_canvas, :multiply, 1.0)
      Transitions.push(blended, target, direction: :bottom, separation: 0)
    end

    mole_spawn_duration_ms = param(:mole_spawn_duration_ms, 300) * game.difficulty

    Animator.animate(
      animation_id: {:mole_down, panel},
      app_pid: self(),
      canvas: blank_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: mole_spawn_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )
  end

  defp whack_success_animation(game, panel) do
    whack_canvas = background_canvas(game, 120, 50, 50)

    transition_fun = fn start, _ -> [start, whack_canvas, start] end
    whack_duration = param(:whack_duration, 100)

    Animator.animate(
      animation_id: {:whack_success, panel},
      app_pid: self(),
      canvas: whack_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: whack_duration,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    InputAdapter.send_light_event(panel + 1, 500)

    # Schedule down animation to start after whack animation completes
    :timer.send_after(whack_duration + 50, {:start_down_animation, panel})
  end

  defp whack_fail_animation(game, panel, _hit?) do
    whack_canvas = background_canvas(game, 0, 75, 50)

    transition_fun = fn start, _ -> [start, whack_canvas, start] end
    whack_duration = param(:whack_duration, 100)

    Animator.animate(
      animation_id: {:whack_fail, panel},
      app_pid: self(),
      canvas: whack_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: whack_duration,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    InputAdapter.send_light_event(panel + 1, 500)
  end

  defp start_game_over_animation(game) do
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    game_over =
      Canvas.new(10 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, "GAME OVER", game.font, 1)

    Animator.animate(
      animation_id: {:game_over},
      app_pid: self(),
      canvas: game_over,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {10 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule score animation
    :timer.send_after(duration + 1000, {:start_score_animation})
  end

  defp clear_all_animators(game) do
    Enum.each(Map.keys(game.active_animators), fn animation_id ->
      Animator.clear(animation_id)
    end)

    # Clear the display
    blank_canvas = Canvas.new(game.display_info.width, game.display_info.height)
    send(self(), {:clear_display, blank_canvas})

    :ok
  end

  defp background_canvas(game, h, s, v) do
    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.HSV.to_rgb(%Chameleon.HSV{h: h, s: s, v: v})

    Canvas.new(game.panel_width, game.panel_height)
    |> Canvas.fill({r, g, b})
    |> Canvas.put_pixel({0, 0}, {0, 0, 0})
    |> Canvas.put_pixel({0, game.panel_height - 1}, {0, 0, 0})
    |> Canvas.put_pixel({game.panel_width - 1, 0}, {0, 0, 0})
    |> Canvas.put_pixel({game.panel_width - 1, game.panel_height - 1}, {0, 0, 0})
  end

  def read_highscore() do
    highscore_path = File.cwd!() |> Path.join(@highscore_file)

    if File.exists?(highscore_path) do
      File.read!(highscore_path) |> String.to_integer()
    else
      write_highscore(0)
      0
    end
  end

  def write_highscore(score) do
    highscore_path = File.cwd!() |> Path.join(@highscore_file)
    File.write!(highscore_path, score |> to_string())
  end
end
