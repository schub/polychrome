defmodule Octopus.KioskModeManager do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, AppManager, PlaylistScheduler, InputAdapter}
  alias Octopus.Events.Event.Controller, as: ControllerEvent
  alias Octopus.PlaylistScheduler.Playlist

  @game Octopus.Apps.Whackamole
  @playlist_name "Default"

  @idle_animation_interval 2_000
  @idle_animation_duration 3_000

  @topic "kiosk_mode_manager"

  defmodule State do
    # statuses: :game, :playlist, :off
    defstruct status: :off,
              game_app_id: nil,
              playlist_id: nil
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start() do
    GenServer.cast(__MODULE__, :start)
  end

  def stop() do
    GenServer.cast(__MODULE__, :stop)
  end

  def is_started?() do
    GenServer.call(__MODULE__, :is_started?)
  end

  @doc """
  Subscribes to the kiosk_mode_manager topic.

  Published messages:
  * `{:kiosk_mode_manager, :started}` - kiosk mode was started
  * `{:kiosk_mode_manager, :stopped}` - kiosk mode was stopped
  """
  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  def handle_input(%ControllerEvent{} = controller_event) do
    GenServer.cast(__MODULE__, {:input_event, controller_event})
  end

  def game_finished() do
    GenServer.cast(__MODULE__, :game_finished)
  end

  def init(:ok) do
    case Application.fetch_env(:octopus, :enable_event_mode) do
      {:ok, true} ->
        Logger.info("KioskModeManager: event mode enabled. Starting")
        start()

      _ ->
        :noop
    end

    playlist_id =
      PlaylistScheduler.list_playlists()
      |> Enum.find(fn %Playlist{name: name} -> name == @playlist_name end)
      |> case do
        %Playlist{id: id} ->
          Logger.info("KioskModeManager: using playlist #{@playlist_name} with id #{id}")
          id

        _ ->
          nil
      end

    :timer.send_interval(@idle_animation_interval, :idle)

    {:ok, %State{status: :off, playlist_id: playlist_id}}
  end

  def handle_cast(:start, %State{status: :off} = state) do
    PlaylistScheduler.start_playlist(state.playlist_id)
    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:kiosk_mode_manager, :started})
    {:noreply, %State{state | status: :playlist}}
  end

  def handle_cast(:start, state) do
    {:noreply, state}
  end

  def handle_cast(:stop, %State{} = state) do
    AppSupervisor.stop_app(state.game_app_id)
    PlaylistScheduler.pause_playlist()
    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:kiosk_mode_manager, :stopped})
    {:noreply, %State{state | status: :off}}
  end

  # Handle new button format - any button press starts the game
  def handle_cast(
        {:input_event, %ControllerEvent{type: :button, action: :press}},
        %State{status: :playlist} = state
      ) do
    Logger.info("KioskModeManager: game button pressed, starting game")

    PlaylistScheduler.pause_playlist()
    {:ok, app_id} = AppSupervisor.start_app(@game)
    AppManager.select_app(app_id)

    {:noreply, %State{state | status: :game, game_app_id: app_id}}
  end

  def handle_cast({:input_event, %ControllerEvent{}}, state) do
    {:noreply, state}
  end

  def handle_cast(:game_finished, %State{status: :game} = state) do
    Logger.info("KioskModeManager: game finished, starting playlist")

    AppSupervisor.stop_app(state.game_app_id)
    PlaylistScheduler.resume_playlist()

    {:noreply, %State{state | status: :playlist}}
  end

  def handle_cast(:game_finished, state), do: {:noreply, state}

  def handle_call(:is_started?, _, %State{status: :off} = state), do: {:reply, false, state}
  def handle_call(:is_started?, _, state), do: {:reply, true, state}

  def handle_info(:idle, %State{status: :playlist} = state) do
    num_buttons = Octopus.installation().num_buttons()
    InputAdapter.send_light_event(Enum.random(1..num_buttons), @idle_animation_duration)

    {:noreply, state}
  end

  def handle_info(:idle, state) do
    {:noreply, state}
  end
end
