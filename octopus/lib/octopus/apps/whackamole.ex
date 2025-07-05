defmodule Octopus.Apps.Whackamole do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Apps.Whackamole.Game
  alias Octopus.Installation

  @tick_every_ms 100
  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule State do
    defstruct [:game]
  end

  def name(), do: "Whack'em"

  def icon(), do: Canvas.from_string("W", Font.load("cshk-Captain Sky Hawk (RARE)"), 3)

  def compatible?() do
    # Game works with any number of panels >= 3 for meaningful gameplay
    Installation.num_panels() >= 3
  end

  def app_init(_) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Initialize game after display configuration
    state = %State{game: Game.new()}

    :timer.send_interval(@tick_every_ms, :tick)
    # Add frame rendering timer for smooth animations
    :timer.send_interval(@frame_time_ms, :render_frame)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    game = Game.tick(state.game)

    {:noreply, %State{state | game: game}}
  end

  def handle_info(:render_frame, %State{} = state) do
    # Render the current game state with animations
    canvas = Game.render_canvas(state.game)

    Octopus.App.update_display(canvas)

    # Clean up expired animations
    game = Game.cleanup_expired_animations(state.game)

    {:noreply, %State{state | game: game}}
  end

  def handle_info({:trigger_down_animation, pannel}, %State{} = state) do
    game = Game.down_animation(state.game, pannel)
    {:noreply, %State{state | game: game}}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button},
        %State{} = state
      ) do
    # Check if button is within valid range for current panel count
    if button >= 1 and button <= state.game.panel_count do
      button_number = button - 1
      game = Game.whack(state.game, button_number, self())
      {:noreply, %State{state | game: game}}
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
end
