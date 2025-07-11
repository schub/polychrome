defmodule Octopus.AppSupervisor do
  use DynamicSupervisor
  require Logger

  alias Octopus.{AppManager, App}
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  @topic "apps"

  @moduledoc """
  The AppRegistry is a DynamicSupervisor that keeps track of all running apps.

  Each app gets a unique app_id that is used in the mixer to select the frames.
  """

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Subscribes to the apps topic.

  Published messages:
  * `{:apps, {:started, app_id, module}}` - an app was started
  * `{:apps, {:stopped, app_id}}` - an app was stopped
  """
  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  @doc """
  Lists all avaiable apps. An app is available if it uses the `Octopus.App` behaviour.
  """
  def available_apps() do
    {:ok, modules} = :application.get_key(:octopus, :modules)

    Enum.filter(modules, fn module ->
      try do
        Octopus.App in (module.__info__(:attributes)[:behaviour] || [])
      rescue
        _ -> false
      end
    end)
  end

  @doc """
  Starts an app and assigns a unique app_id. It is possible to start multiple instances of the same app.
  Checks app compatibility before starting.
  """
  def start_app(module, opts \\ []) when is_atom(module) do
    cond do
      module not in available_apps() ->
        Logger.error("App #{module} not found")
        {:error, :app_not_found}

      not apply(module, :compatible?, []) ->
        Logger.info("App #{module} is not compatible with current installation")
        {:error, :incompatible}

      true ->
        default_config = apply(module, :config_schema, []) |> App.default_config()
        config = Keyword.get(opts, :config, %{})
        config = Map.merge(default_config, config)
        do_start_app(module, config)
    end
  end

  @doc """
  Starts an app if not already running, otherwise returns the existing app_id.
  This prevents duplicate instances of the same app module.
  """
  def start_or_select_app(module, opts \\ []) when is_atom(module) do
    case find_running_app(module) do
      {:ok, existing_app_id} ->
        Logger.info("App #{module} already running with id #{existing_app_id}, selecting it")
        {:ok, existing_app_id}

      :not_found ->
        start_app(module, opts)
    end
  end

  @doc """
  Finds a running app by module. Returns {:ok, app_id} if found, :not_found otherwise.
  """
  def find_running_app(module) when is_atom(module) do
    case Enum.find(running_apps(), fn {mod, _app_id} -> mod == module end) do
      {^module, app_id} -> {:ok, app_id}
      nil -> :not_found
    end
  end

  defp do_start_app(module, config) when is_atom(module) do
    app_id = generate_app_id()
    name = {:via, Registry, {Octopus.AppRegistry, app_id, module}}

    # select app in AppManager if there is no other app running
    if running_apps() == [] do
      AppManager.select_app(app_id)
    end

    case DynamicSupervisor.start_child(__MODULE__, {module, {config, name: name}}) do
      {:ok, _pid} ->
        Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:apps, {:started, app_id, module}})
        {:ok, app_id}

      {:error, error} ->
        Logger.error("Could not start app #{module}: #{inspect(error)}")
        {:error, :start_failed}
    end
  end

  @doc """
  List all running apps with their app_id.
  """
  def running_apps() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, [module]} ->
      [app_id] = Registry.keys(Octopus.AppRegistry, pid)
      {module, app_id}
    end)
  end

  @doc """
  Stops an specific instance of an app.
  """
  def stop_app(app_id) do
    if app_id == AppManager.get_selected_app() do
      GenServer.cast(Octopus.Mixer, :stop_audio_playback)
    end

    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:apps, {:stopped, app_id}})

    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        Logger.warning("App #{app_id} not found")
        :ok
    end
  end

  def update_config(app_id, config) when is_binary(app_id) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        :ok = GenServer.call(pid, {:update_config, config})

        Phoenix.PubSub.broadcast(
          Octopus.PubSub,
          @topic,
          {:apps, {:config_updated, app_id, config}}
        )

      [] ->
        Logger.warning("App #{app_id} not found")
        :ok
    end
  end

  def config(app_id) when is_binary(app_id) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        GenServer.call(pid, :get_config)

      [] ->
        Logger.warning("App #{app_id} not found")
        :ok
    end
  end

  @doc """
  Stops all running apps.
  """
  def stop_all_apps() do
    running_apps()
    |> Enum.map(fn {_, app_id} -> stop_app(app_id) end)
  end

  @doc """
  Looks up the pid and module for a given app_id.
  """
  @spec lookup_app(binary()) :: {pid(), atom()}
  def lookup_app(app_id) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, module}] -> {pid, module}
      [] -> raise "App #{app_id} not found"
    end
  end

  @doc """
  Looks up the app_id for a given pid.
  """
  def lookup_app_id(pid) do
    case Registry.keys(Octopus.AppRegistry, pid) do
      [app_id] -> app_id
      [] -> raise "Process has no app_id"
    end
  end

  @doc """
  Sends an event to an app. Ignores the event if the app is not running.
  """
  def send_event(app_id, %event_type{} = event)
      when event_type in [InputEvent, LifecycleEvent, AudioEvent, ProximityEvent] do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] -> send(pid, {:event, event})
      [] -> :noop
    end
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp generate_app_id() do
    alphabet = Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9)
    Enum.map(1..6, fn _ -> Enum.random(alphabet) end) |> to_string()
  end
end
