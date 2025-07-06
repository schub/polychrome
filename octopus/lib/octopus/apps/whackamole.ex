defmodule Octopus.Apps.Whackamole do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Apps.Whackamole.Game
  alias Octopus.Animator
  alias Octopus.Transitions

  defmodule State do
    defstruct [:game, :display_info]
  end

  def name(), do: "Whack'em"

  def icon(), do: Canvas.from_string("W", Font.load("cshk-Captain Sky Hawk (RARE)"), 3)

  def compatible?() do
    # Game works with any number of panels >= 3 for meaningful gameplay
    # and requires 8x8 pixel panels for proper mole sprite display
    installation_info = Octopus.App.get_installation_info()

    installation_info.panel_count >= 3 and
      installation_info.panel_width == 8 and
      installation_info.panel_height == 8
  end

  def app_init(_) do
    Logger.info("WhackAMole app_init starting")
    # Configure display using modern unified API - adjacent layout for whackamole panels
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Get display info for the game to use
    display_info = Octopus.App.get_display_info()
    Logger.info("Display info: #{inspect(display_info)}")

    game = Game.new(display_info)
    Logger.info("Game created with state: #{game.state}")

    # Start the intro sequence immediately and update the game state
    updated_game = Game.start_intro(game, self())
    Logger.info("Game after start_intro: #{updated_game.state}")

    state = %State{
      game: updated_game,
      display_info: display_info
    }

    Logger.info("WhackAMole app_init complete")
    {:ok, state}
  end

  def handle_info({:intro_complete}, %State{} = state) do
    Logger.info("Intro complete - transitioning to playing state")
    # Transition from intro to playing state
    updated_game = Game.start_playing(state.game)
    Logger.info("Game transitioned to: #{updated_game.state}")
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:game_over}, %State{} = state) do
    # Transition to game over state
    updated_game = Game.start_game_over(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:start_tilt}, %State{} = state) do
    # Start tilt sequence
    updated_game = Game.start_tilt(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:end_tilt}, %State{} = state) do
    # End tilt and return to playing
    updated_game = Game.end_tilt(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:mole_timeout, panel}, %State{} = state) do
    # Handle mole timeout
    updated_game = Game.handle_mole_timeout(state.game, panel)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:spawn_mole}, %State{} = state) do
    Logger.info("Spawning mole in state: #{state.game.state}")
    # Spawn a new mole
    updated_game = Game.maybe_spawn_mole(state.game)

    # Schedule next mole spawn
    Game.schedule_next_mole_spawn(updated_game)

    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:start_down_animation, panel}, %State{} = state) do
    # Start the down animation for the specified panel
    Game.start_down_animation(state.game, panel)
    {:noreply, state}
  end

  def handle_info({:clear_display, canvas}, %State{} = state) do
    # Clear the display with the provided blank canvas
    Octopus.App.update_display(canvas, :rgb, easing_interval: 0)

    # Update the game state to reflect the cleared display
    updated_game = %{state.game | display_canvas: canvas, panel_canvases: %{}}
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:clear_panel_canvas, panel}, %State{} = state) do
    # Clear the specific panel canvas
    updated_state = clear_panel_canvas(state, panel)
    {:noreply, updated_state}
  end

  def handle_info({:start_intro_em}, %State{} = state) do
    Logger.info("Starting intro 'EM! animation")
    # Start the "'EM!" animation
    game = state.game
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    a =
      Canvas.new(4 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, "'EM!", game.font, 1)

    Animator.animate(
      animation_id: {:intro_em},
      app_pid: self(),
      canvas: a,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {4 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule intro completion
    Logger.info("Scheduling intro completion in #{duration + 100}ms")
    :timer.send_after(duration + 100, {:intro_complete})

    {:noreply, state}
  end

  def handle_info({:start_score_animation}, %State{} = state) do
    # Start score animation
    game = state.game
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    text = " SCORE #{game.score |> to_string()}"

    score =
      Canvas.new(10 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, text, game.font, 2)

    Animator.animate(
      animation_id: {:score},
      app_pid: self(),
      canvas: score,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {10 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule highscore animation
    :timer.send_after(duration + 1000, {:start_highscore_animation})

    {:noreply, state}
  end

  def handle_info({:start_highscore_animation}, %State{} = state) do
    # Start highscore animation
    game = state.game
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    canvas =
      if game.score > game.highscore do
        Game.write_highscore(game.score)

        Canvas.new(10 * game.panel_width, game.panel_height)
        |> Canvas.put_string({0, 0}, "HIGHSCORE!", game.font, 0)
      else
        Canvas.new(10 * game.panel_width, game.panel_height)
        |> Canvas.put_string({0, 0}, " HIGH #{game.highscore}", game.font, 0)
      end

    Animator.animate(
      animation_id: {:highscore},
      app_pid: self(),
      canvas: canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {10 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule game over completion
    :timer.send_after(duration + 1000, {:game_over_complete})

    {:noreply, state}
  end

  def handle_info({:game_over_complete}, %State{} = state) do
    # Game over sequence complete
    Octopus.KioskModeManager.game_finished()
    {:noreply, state}
  end

  def handle_info({:animator_update, animation_id, canvas, frame_status}, %State{} = state) do
    Logger.debug("Animator update: #{inspect(animation_id)}, frame_status: #{frame_status}")
    # Handle canvas updates from the Animator module with animation identification
    updated_state =
      case animation_id do
        {:mole_spawn, panel} ->
          update_panel_canvas(state, panel, canvas, frame_status)

        {:mole_lost, panel} ->
          update_panel_canvas(state, panel, canvas, frame_status)

        {:mole_down, panel} ->
          update_panel_canvas(state, panel, canvas, frame_status)

        {:whack_success, panel} ->
          update_panel_canvas(state, panel, canvas, frame_status)

        {:whack_fail, panel} ->
          update_panel_canvas(state, panel, canvas, frame_status)

        {:intro_whack} ->
          # Handle intro "WHACK" text - overlay on existing display
          overlay_on_display(state, canvas, {0, 0}, frame_status)

        {:intro_em} ->
          # Handle intro "'EM!" text - overlay after "WHACK"
          panel_width = state.display_info.panel_width
          overlay_on_display(state, canvas, {6 * panel_width, 0}, frame_status)

        {:game_over} ->
          # Handle game over text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        {:score} ->
          # Handle score text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        {:highscore} ->
          # Handle highscore text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        {:tilt} ->
          # Handle tilt text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        _ ->
          # For unknown animations, just update display directly
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state
      end

    {:noreply, updated_state}
  end

  def handle_info(msg, %State{} = state) do
    Logger.warning("Unexpected message in WhackAMole: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button},
        %State{} = state
      ) do
    # Check if button is within valid range for current installation
    installation_info = Octopus.App.get_installation_info()

    if button >= 1 and button <= installation_info.panel_count do
      button_number = button - 1
      updated_game = Game.handle_whack(state.game, button_number)
      {:noreply, %State{state | game: updated_game}}
    else
      # Button outside valid range - ignore
      {:noreply, state}
    end
  end

  def handle_event(%InputEvent{}, %State{} = state) do
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp update_panel_canvas(state, panel, canvas, _frame_status) do
    # Update the panel canvas in the game state
    game = state.game
    updated_panel_canvases = Map.put(game.panel_canvases, panel, canvas)

    # Compose the full display from all panel canvases
    new_display_canvas = compose_full_display(updated_panel_canvases, state.display_info)

    # Always update display when panels change
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{
      game
      | panel_canvases: updated_panel_canvases,
        display_canvas: new_display_canvas
    }

    %{state | game: updated_game}
  end

  defp overlay_on_display(state, canvas, {x, y}, _frame_status) do
    # For intro text, overlay on the current display canvas
    game = state.game
    new_display_canvas = Canvas.overlay(game.display_canvas, canvas, offset: {x, y})

    # Update display with the overlaid canvas
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{game | display_canvas: new_display_canvas}
    %{state | game: updated_game}
  end

  defp compose_full_display(panel_canvases, display_info) do
    # Create blank canvas
    display_canvas = Canvas.new(display_info.width, display_info.height)

    # Overlay each panel canvas at the correct position
    Enum.reduce(panel_canvases, display_canvas, fn {panel_index, panel_canvas}, acc ->
      x_offset = panel_index * display_info.panel_width
      Canvas.overlay(acc, panel_canvas, offset: {x_offset, 0})
    end)
  end

  defp clear_panel_canvas(state, panel) do
    # Remove the panel canvas and update display
    game = state.game
    updated_panel_canvases = Map.delete(game.panel_canvases, panel)

    # Compose the full display from remaining panel canvases
    new_display_canvas = compose_full_display(updated_panel_canvases, state.display_info)

    # Update display
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{
      game
      | panel_canvases: updated_panel_canvases,
        display_canvas: new_display_canvas
    }

    %{state | game: updated_game}
  end
end
