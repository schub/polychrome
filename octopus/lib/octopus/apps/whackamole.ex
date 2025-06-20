defmodule Octopus.Apps.Whackamole do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.ControllerEvent
  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Apps.Whackamole.Game

  @tick_every_ms 100

  defmodule State do
    defstruct [:game]
  end

  def name(), do: "Whack'em"

  def icon(), do: Canvas.from_string("W", Font.load("cshk-Captain Sky Hawk (RARE)"), 3)

  def app_init(_) do
    state = %State{game: Game.new()}

    :timer.send_interval(@tick_every_ms, :tick)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    game = Game.tick(state.game)

    {:noreply, %State{state | game: game}}
  end

  def handle_input(
        %ControllerEvent{type: :button, action: :press, button: button},
        %State{} = state
      )
      when button >= 1 and button <= 10 do
    button_number = button - 1

    game = Game.whack(state.game, button_number)

    {:noreply, %State{state | game: game}}
  end

  def handle_input(%ControllerEvent{}, %State{} = state) do
    {:noreply, state}
  end
end
