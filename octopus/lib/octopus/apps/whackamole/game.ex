defmodule Octopus.Apps.Whackamole.Game do
  use Octopus.Params, prefix: :whackamole
  require Logger
  alias Octopus.{Canvas, Font, TimeAnimator, Sprite, KioskModeManager, InputAdapter}
  alias Octopus.Apps.Whackamole.Mole

  defstruct [
    :state,
    :tick,
    :score,
    :font,
    :lives,
    :moles,
    :last_mole,
    :difficulty,
    :whack_times,
    :tilt_start,
    :highscore,
    # TimeAnimator-based animation tracking
    :animations,
    :base_canvas,
    # Dynamic panel configuration
    :panel_count
  ]

  # game_states [:intro, :playing, :game_over, :tilt]

  @font_name "cshk-Captain Sky Hawk (RARE)"
  @sprite_sheet "256-characters-original"
  @highscore_file "whackamole_highscore"
  # 56..59
  @mole_sprites 0..255

  def new() do
    # Get display info for canvas dimensions
    display_info = Octopus.App.get_display_info()
    base_canvas = Canvas.new(display_info.width, display_info.height)
    panel_count = display_info.panel_count

    Logger.info(
      "WhackAMole: Initializing game with canvas size #{display_info.width}x#{display_info.height}, #{panel_count} panels"
    )

    %__MODULE__{
      state: :intro,
      lives: 3,
      font: Font.load(@font_name),
      tick: 0,
      score: 0,
      difficulty: 1,
      last_mole: 0,
      moles: %{},
      whack_times: [],
      highscore: read_highscore(),
      animations: %{},
      base_canvas: base_canvas,
      panel_count: panel_count
    }
  end

  def tick(%__MODULE__{state: :intro} = game) do
    case game.tick do
      3 ->
        Logger.info("WhackAMole: Starting intro whack animation at tick #{game.tick}")

        # Create first part of intro text with font variant 0
        intro_text1 = "WHACK"
        intro_text2 = "'EM!"

        # Calculate center position for both texts together
        center_x = center_text_two_parts(intro_text1, intro_text2, game.base_canvas.width)

        whack_canvas =
          Canvas.new(String.length(intro_text1) * 8, 8)
          |> Canvas.put_string({0, 0}, intro_text1, game.font, 0)

        # Show for 4 seconds (4000ms)
        game = start_animation(game, :intro_whack, whack_canvas, {center_x, 0}, :push, :top, 4000)

        Logger.info(
          "WhackAMole: Intro whack animation started, animations count: #{map_size(game.animations)}"
        )

        next_tick(game)

      18 ->
        Logger.info("WhackAMole: Starting intro 'EM animation at tick #{game.tick}")

        # Create second part of intro text with font variant 1
        intro_text1 = "WHACK"
        intro_text2 = "'EM!"

        # Calculate positions for both texts centered together
        center_x = center_text_two_parts(intro_text1, intro_text2, game.base_canvas.width)
        em_x = center_x + String.length(intro_text1) * 8

        em_canvas =
          Canvas.new(String.length(intro_text2) * 8, 8)
          |> Canvas.put_string({0, 0}, intro_text2, game.font, 1)

        # Show for 3.5 seconds (3500ms) - both texts should disappear together
        game = start_animation(game, :intro_em, em_canvas, {em_x, 0}, :push, :top, 3500)

        Logger.info(
          "WhackAMole: Intro 'EM animation started, animations count: #{map_size(game.animations)}"
        )

        next_tick(game)

      60 ->
        Logger.info("WhackAMole: Intro complete, switching to playing state")
        # Clear any remaining intro animations and start gameplay
        game = clear_animations(game)
        %__MODULE__{game | state: :playing, tick: 0}

      _ ->
        next_tick(game)
    end
  end

  def tick(%__MODULE__{state: :playing} = game) do
    game
    |> mole_survived?()
    |> case do
      %__MODULE__{lives: lives} = game when lives > 0 ->
        game
        |> check_tilt()
        |> maybe_add_mole()
        |> maybe_increase_difficulty()
        |> next_tick()

      _ ->
        %__MODULE__{game | state: :game_over, tick: 0}
    end
  end

  def tick(%__MODULE__{state: :game_over} = game) do
    case game.tick do
      1 ->
        # Clear all animations (including active sprite animations) immediately when game ends
        game = clear_animations(game)
        next_tick(game)

      10 ->
        # Create game over text that fits the available width
        game_over_text = "GAME OVER"
        text_width = min(String.length(game_over_text) * 8, game.base_canvas.width)
        center_x = center_text(game_over_text, game.base_canvas.width)

        game_over =
          Canvas.new(text_width, 8)
          |> Canvas.put_string({0, 0}, game_over_text, game.font, 1)

        # Show for 3 seconds (3000ms)
        game = start_animation(game, :game_over_text, game_over, {center_x, 0}, :push, :top, 3000)
        next_tick(game)

      50 ->
        text = "SCORE #{game.score |> to_string()}"
        text_width = min(String.length(text) * 8, game.base_canvas.width)
        center_x = center_text(text, game.base_canvas.width)

        score =
          Canvas.new(text_width, 8)
          |> Canvas.put_string({0, 0}, text, game.font, 2)

        # Show for 3 seconds (3000ms)
        game = start_animation(game, :score_text, score, {center_x, 0}, :push, :top, 3000)
        next_tick(game)

      90 ->
        {canvas, center_x} =
          if game.score > game.highscore do
            write_highscore(game.score)
            highscore_text = "HI-SCORE!"
            text_width = min(String.length(highscore_text) * 8, game.base_canvas.width)
            center_x = center_text(highscore_text, game.base_canvas.width)

            canvas =
              Canvas.new(text_width, 8)
              |> Canvas.put_string({0, 0}, highscore_text, game.font, 0)

            {canvas, center_x}
          else
            highscore_text = "HI-SCORE #{game.highscore}"
            text_width = min(String.length(highscore_text) * 8, game.base_canvas.width)
            center_x = center_text(highscore_text, game.base_canvas.width)

            canvas =
              Canvas.new(text_width, 8)
              |> Canvas.put_string({0, 0}, highscore_text, game.font, 0)

            {canvas, center_x}
          end

        # Show for 3 seconds (3000ms)
        game = start_animation(game, :highscore_text, canvas, {center_x, 0}, :push, :top, 3000)
        next_tick(game)

      130 ->
        KioskModeManager.game_finished()
        next_tick(game)

      _ ->
        next_tick(game)
    end
  end

  def tick(%__MODULE__{state: :tilt} = game) do
    case game.tick - game.tilt_start do
      1 ->
        # Clear all existing animations when tilt starts
        game = clear_animations(game)

        tilt_text = "TILT!"
        text_width = min(String.length(tilt_text) * 8, game.base_canvas.width)
        center_x = center_text(tilt_text, game.base_canvas.width)

        tilt =
          Canvas.new(text_width, 8)
          |> Canvas.put_string({0, 0}, tilt_text, game.font, 3)

        # Show tilt for 3 seconds (3000ms)
        game = start_blinking_animation(game, :tilt_text, tilt, {center_x, 0}, 3000)
        next_tick(game)

      30 ->
        # Clear tilt animation and return to playing
        game = clear_animations(game)
        %__MODULE__{game | state: :playing}

      _ ->
        next_tick(game)
    end
  end

  def whack(game, button_number, app_pid \\ nil)

  def whack(%__MODULE__{state: :playing} = game, button_number, app_pid) do
    if Map.has_key?(game.moles, button_number) do
      moles = Map.delete(game.moles, button_number)
      score = game.score + 1

      # Remove the spawn animation for this panel
      animations_without_spawn = Map.delete(game.animations, {:spawn, button_number})
      game_without_spawn = %__MODULE__{game | animations: animations_without_spawn}

      # Add whack success animation
      game_with_whack = whack_success_animation(game_without_spawn, button_number, app_pid)

      %__MODULE__{game_with_whack | moles: moles, score: score}
    else
      game_with_fail = whack_fail_animation(game, button_number, false)
      now = System.os_time(:millisecond)
      %__MODULE__{game_with_fail | whack_times: [now | game.whack_times]}
    end
  end

  def whack(%__MODULE__{} = game, _, _), do: game

  def next_tick(%__MODULE__{tick: tick} = game) do
    %__MODULE__{game | tick: tick + 1}
  end

  def check_tilt(%__MODULE__{} = game) do
    tilt_duration_ms = param(:tilt_duration_ms, 1000)
    tilt_max = param(:tilt_max, 6)
    now = System.os_time(:millisecond)

    {_expired, active} =
      Enum.split_with(game.whack_times, fn time ->
        now - time > tilt_duration_ms
      end)

    case Enum.count(active) do
      count when count > tilt_max ->
        %__MODULE__{
          game
          | lives: game.lives - 1,
            whack_times: [],
            state: :tilt,
            tilt_start: game.tick
        }

      _ ->
        %__MODULE__{game | whack_times: active}
    end
  end

  def maybe_add_mole(%__MODULE__{} = game) do
    mole_delay_s = param(:mole_delay_s, 1.5)
    spread = 0.3
    value = mole_delay_s * 10 * game.difficulty
    diff = value * spread
    min = value - diff
    target = :rand.uniform() * diff + min

    if game.tick - game.last_mole > target do
      pannels_with_moles = Map.keys(game.moles)

      case Enum.to_list(0..(game.panel_count - 1)) -- pannels_with_moles do
        [] ->
          Logger.error("No free pannels")
          game

        free_pannels ->
          pannel = Enum.random(free_pannels)
          moles = Map.put(game.moles, pannel, Mole.new(pannel, game.tick))
          game_with_animation = spawn_animation(game, pannel)

          %__MODULE__{game_with_animation | moles: moles, last_mole: game.tick}
      end
    else
      game
    end
  end

  def maybe_increase_difficulty(%__MODULE__{} = game) do
    increment_difficulty_every_s = param(:increment_difficulty_every_s, 4)
    difficulty_decay = param(:difficulty_decay, 0.04)

    if rem(game.tick, increment_difficulty_every_s * 10) == 0 do
      difficulty =
        :math.exp(game.tick / increment_difficulty_every_s / 10 * difficulty_decay * -1)

      Logger.info("Difficulty increased from #{game.difficulty} to #{difficulty}")
      %__MODULE__{game | difficulty: difficulty}
    else
      game
    end
  end

  def mole_survived?(%__MODULE__{} = game) do
    mole_time_to_live_s = param(:mole_time_to_live_s, 7)

    {survived, active} =
      Enum.split_with(game.moles, fn {_, mole} ->
        game.tick - mole.start_tick > mole_time_to_live_s * 10 * game.difficulty
      end)

    # For each survived mole, remove its spawn animation and add lost animation
    game_with_lost_animations =
      survived
      |> Enum.reduce(game, fn {pannel, %Mole{} = mole}, acc_game ->
        # Remove the spawn animation for this panel
        animations_without_spawn = Map.delete(acc_game.animations, {:spawn, pannel})
        game_without_spawn = %__MODULE__{acc_game | animations: animations_without_spawn}

        # Add lost animation
        lost_animation(game_without_spawn, mole)
      end)

    moles = Enum.into(active, %{})

    %__MODULE__{
      game_with_lost_animations
      | moles: moles,
        lives: game.lives - Enum.count(survived)
    }
  end

  # TimeAnimator-based animation functions

  def cleanup_expired_animations(%__MODULE__{} = game) do
    current_time = System.monotonic_time(:millisecond)

    active_animations =
      Enum.filter(game.animations, fn {_id, animation} ->
        elapsed = current_time - animation.start_time
        total_duration = animation.total_duration
        elapsed < total_duration
      end)
      |> Map.new()

    %__MODULE__{game | animations: active_animations}
  end

  def render_canvas(%__MODULE__{} = game) do
    current_time = System.monotonic_time(:millisecond)
    result_canvas = Canvas.clear(game.base_canvas)

    # First render the game state content (moles, etc.)
    result_canvas = render_game_content(result_canvas, game)

    # Then render all active animations on top
    final_canvas =
      Enum.reduce(game.animations, result_canvas, fn {_id, animation}, canvas_acc ->
        case evaluate_animation(animation, current_time) do
          {:active, animated_canvas} ->
            Canvas.overlay(canvas_acc, animated_canvas, offset: animation.position)

          :expired ->
            canvas_acc
        end
      end)

    final_canvas
  end

  defp render_game_content(canvas, %__MODULE__{state: :playing} = _game) do
    # During gameplay, moles are rendered through animations only
    # Static mole rendering is handled by spawn/down animations
    canvas
  end

  defp render_game_content(canvas, %__MODULE__{state: state})
       when state in [:intro, :game_over, :tilt] do
    # For intro, game_over, and tilt states, ensure canvas is cleared
    # Only animations should be visible
    Canvas.clear(canvas)
  end

  defp render_game_content(canvas, %__MODULE__{}) do
    # Fallback for any other states
    Canvas.clear(canvas)
  end

  defp start_animation(
         game,
         id,
         target_canvas,
         position,
         transition_type,
         direction,
         total_duration
       ) do
    # Ensure consistent canvas size - use 8x8 for individual panel animations
    panel_width = 8
    panel_height = 8

    {adjusted_canvas, adjusted_position} =
      case target_canvas.width do
        w when w > panel_width ->
          # This is a text canvas spanning multiple panels - keep as is
          {target_canvas, position}

        _ ->
          # This is a single panel canvas - ensure it's exactly 8x8
          resized = Canvas.new(panel_width, panel_height)
          resized = Canvas.overlay(resized, target_canvas)
          {resized, position}
      end

    # Create source canvas with same dimensions as target
    current_canvas = Canvas.new(adjusted_canvas.width, adjusted_canvas.height)

    # For text animations (intro, game over), use quick transition but long hold time
    transition_duration =
      cond do
        String.starts_with?(to_string(id), "intro_") -> 800
        String.contains?(to_string(id), "_text") -> 800
        true -> total_duration
      end

    animation = %{
      id: id,
      source_canvas: current_canvas,
      target_canvas: adjusted_canvas,
      position: adjusted_position,
      transition_type: transition_type,
      direction: direction,
      transition_duration: transition_duration,
      total_duration: total_duration,
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(game.animations, id, animation)
    %__MODULE__{game | animations: animations}
  end

  defp start_blinking_animation(game, id, canvas, position, duration) do
    # Ensure consistent canvas size
    panel_width = 8
    panel_height = 8

    {adjusted_canvas, adjusted_position} =
      case canvas.width do
        w when w > panel_width ->
          # This is a text canvas spanning multiple panels - keep as is
          {canvas, position}

        _ ->
          # This is a single panel canvas - ensure it's exactly 8x8
          resized = Canvas.new(panel_width, panel_height)
          resized = Canvas.overlay(resized, canvas)
          {resized, position}
      end

    blank_canvas = Canvas.new(adjusted_canvas.width, adjusted_canvas.height)

    animation = %{
      id: id,
      source_canvas: adjusted_canvas,
      target_canvas: blank_canvas,
      position: adjusted_position,
      transition_type: :blink,
      direction: nil,
      transition_duration: duration,
      total_duration: duration,
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(game.animations, id, animation)
    %__MODULE__{game | animations: animations}
  end

  defp clear_animations(game) do
    %__MODULE__{game | animations: %{}}
  end

  defp evaluate_animation(animation, current_time) do
    elapsed = current_time - animation.start_time
    transition_duration = Map.get(animation, :transition_duration, animation.total_duration)
    total_duration = animation.total_duration

    cond do
      elapsed < 0 ->
        {:active, animation.source_canvas}

      elapsed >= total_duration ->
        case animation.transition_type do
          :blink -> :expired
          _ -> :expired
        end

      elapsed >= transition_duration ->
        # Transition is complete, hold the target canvas for the remaining duration
        {:active, animation.target_canvas}

      true ->
        # Still in transition phase
        time_progress = elapsed / transition_duration

        animated_canvas =
          case animation.transition_type do
            :blink ->
              # Blink effect: alternate between source and blank
              # 200ms cycle
              cycle_time = 200
              cycle_progress = rem(elapsed, cycle_time) / cycle_time
              if cycle_progress < 0.5, do: animation.source_canvas, else: animation.target_canvas

            transition_type ->
              TimeAnimator.evaluate_transition(
                animation.source_canvas,
                animation.target_canvas,
                time_progress,
                transition_type,
                direction: animation.direction
              )
          end

        {:active, animated_canvas}
    end
  end

  def lost_animation(%__MODULE__{} = game, %Mole{} = mole) do
    red_canvas = background_canvas(0, 100, 100)
    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))

    # Ensure sprite canvas is exactly 8x8
    sprite_canvas =
      if sprite_canvas.width != 8 or sprite_canvas.height != 8 do
        resized = Canvas.new(8, 8)
        Canvas.overlay(resized, sprite_canvas)
      else
        sprite_canvas
      end

    # Create blinking red effect
    animation_id = {:lost, mole.pannel}
    blended = Canvas.blend(sprite_canvas, red_canvas, :multiply, 1.0)

    animation = %{
      id: animation_id,
      source_canvas: blended,
      target_canvas: Canvas.new(8, 8),
      position: {mole.pannel * 8, 0},
      transition_type: :blink,
      direction: nil,
      transition_duration: param(:lost_animation_duration_ms, 500),
      total_duration: param(:lost_animation_duration_ms, 500),
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(game.animations, animation_id, animation)
    %__MODULE__{game | animations: animations}
  end

  def spawn_animation(%__MODULE__{} = game, pannel) do
    show_hints_till = 50

    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))
    # Ensure sprite canvas is exactly 8x8
    sprite_canvas =
      if sprite_canvas.width != 8 or sprite_canvas.height != 8 do
        resized = Canvas.new(8, 8)
        Canvas.overlay(resized, sprite_canvas)
      else
        sprite_canvas
      end

    mole_spawn_duration_ms = trunc(param(:mole_spawn_duration_ms, 800) * game.difficulty)
    # Mole should stay visible for the full time-to-live duration
    mole_time_to_live_s = param(:mole_time_to_live_s, 7)
    mole_visible_duration_ms = trunc(mole_time_to_live_s * 1000 * game.difficulty)

    if game.tick < show_hints_till do
      InputAdapter.send_light_event(pannel + 1, 1000)
    end

    animation_id = {:spawn, pannel}

    animation = %{
      id: animation_id,
      source_canvas: Canvas.new(8, 8),
      target_canvas: sprite_canvas,
      position: {pannel * 8, 0},
      transition_type: :push,
      direction: :top,
      transition_duration: mole_spawn_duration_ms,
      total_duration: mole_visible_duration_ms,
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(game.animations, animation_id, animation)
    %__MODULE__{game | animations: animations}
  end

  def down_animation(%__MODULE__{} = game, pannel) do
    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))
    # Ensure sprite canvas is exactly 8x8
    sprite_canvas =
      if sprite_canvas.width != 8 or sprite_canvas.height != 8 do
        resized = Canvas.new(8, 8)
        Canvas.overlay(resized, sprite_canvas)
      else
        sprite_canvas
      end

    green_canvas = background_canvas(120, 100, 100)
    blended = Canvas.blend(sprite_canvas, green_canvas, :multiply, 1.0)

    mole_spawn_duration_ms = trunc(param(:mole_spawn_duration_ms, 800) * game.difficulty)

    # Remove any existing animations for this panel first
    cleaned_animations =
      game.animations
      |> Map.delete({:spawn, pannel})
      |> Map.delete({:whack_success, pannel})
      |> Map.delete({:whack_fail, pannel})

    animation_id = {:down, pannel}

    animation = %{
      id: animation_id,
      source_canvas: blended,
      target_canvas: Canvas.new(8, 8),
      position: {pannel * 8, 0},
      transition_type: :push,
      direction: :bottom,
      transition_duration: mole_spawn_duration_ms,
      total_duration: mole_spawn_duration_ms,
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(cleaned_animations, animation_id, animation)
    %__MODULE__{game | animations: animations}
  end

  def whack_success_animation(%__MODULE__{} = game, pannel, app_pid) do
    whack_canvas = background_canvas(120, 50, 50)
    whack_duration = param(:whack_duration, 100)

    InputAdapter.send_light_event(pannel + 1, 500)

    # Start immediate flash animation
    animation_id = {:whack_success, pannel}

    animation = %{
      id: animation_id,
      source_canvas: whack_canvas,
      # Ensure consistent size
      target_canvas: Canvas.new(8, 8),
      position: {pannel * 8, 0},
      transition_type: :blink,
      direction: nil,
      transition_duration: whack_duration,
      total_duration: whack_duration,
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(game.animations, animation_id, animation)
    game_with_animation = %__MODULE__{game | animations: animations}

    # Schedule down animation after whack animation - send to WhackAMole app process
    if app_pid do
      spawn(fn ->
        :timer.sleep(whack_duration)
        send(app_pid, {:trigger_down_animation, pannel})
      end)
    end

    game_with_animation
  end

  def whack_fail_animation(%__MODULE__{} = game, pannel, _hit?) do
    whack_canvas = background_canvas(0, 75, 50)
    whack_duration = param(:whack_duration, 100)

    InputAdapter.send_light_event(pannel + 1, 500)

    animation_id = {:whack_fail, pannel}

    animation = %{
      id: animation_id,
      source_canvas: whack_canvas,
      # Ensure consistent size
      target_canvas: Canvas.new(8, 8),
      position: {pannel * 8, 0},
      transition_type: :blink,
      direction: nil,
      transition_duration: whack_duration,
      total_duration: whack_duration,
      start_time: System.monotonic_time(:millisecond)
    }

    animations = Map.put(game.animations, animation_id, animation)
    %__MODULE__{game | animations: animations}
  end

  def background_canvas(h, s, v) do
    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.HSV.to_rgb(%Chameleon.HSV{h: h, s: s, v: v})

    Canvas.new(8, 8)
    |> Canvas.fill({r, g, b})
    |> Canvas.put_pixel({0, 0}, {0, 0, 0})
    |> Canvas.put_pixel({0, 7}, {0, 0, 0})
    |> Canvas.put_pixel({7, 0}, {0, 0, 0})
    |> Canvas.put_pixel({7, 7}, {0, 0, 0})
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

  # Helper function for centering text based on panels (not pixels)
  # This ensures each character appears on a single panel
  defp center_text(text, canvas_width) do
    text_length_in_panels = String.length(text)
    # Each panel is 8 pixels wide
    total_panels = div(canvas_width, 8)

    # Center based on panels, then convert to pixels
    center_panel = max(0, div(total_panels - text_length_in_panels, 2))
    # Convert panel position to pixel position
    center_panel * 8
  end

  # Helper function for centering two-part text (like "WHACK" + "'EM!")
  # Returns the starting position for the first text part
  defp center_text_two_parts(text1, text2, canvas_width) do
    total_text_length = String.length(text1) + String.length(text2)
    total_panels = div(canvas_width, 8)

    # Center the combined text based on panels
    center_panel = max(0, div(total_panels - total_text_length, 2))
    # Convert panel position to pixel position
    center_panel * 8
  end
end
