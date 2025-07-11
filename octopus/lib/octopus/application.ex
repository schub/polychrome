defmodule Octopus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Octopus.{Font, Sprite, Image, WebP}

  @impl true
  def start(_type, _args) do
    children =
      [
        OctopusWeb.Telemetry,
        Octopus.Repo,
        {Phoenix.PubSub, name: Octopus.PubSub},
        {Ecto.Migrator,
         repos: Application.fetch_env!(:octopus, :ecto_repos),
         skip: System.get_env("SKIP_MIGRATIONS") == "true"},
        Octopus.Params,
        %{
          id: Octopus.Params.LoadPersistedConfig,
          start: {Task, :start_link, [fn -> Octopus.Params.load_persisted_config() end]},
          restart: :transient
        },

        # Caches
        Supervisor.child_spec({Cachex, name: Font}, id: make_ref()),
        Supervisor.child_spec({Cachex, name: Sprite}, id: make_ref()),
        Supervisor.child_spec({Cachex, name: Image}, id: make_ref()),
        Supervisor.child_spec({Cachex, name: WebP}, id: make_ref()),

        # Apps
        Octopus.Broadcaster,
        {Registry, keys: :unique, name: Octopus.AppRegistry},
        {Registry, keys: :unique, name: Octopus.Animator},
        Octopus.AppSupervisor,
        Octopus.AppManager,
        Octopus.Events.Router,
        Octopus.Events.Event.Proximity.Processor,
        Octopus.InputAdapter,
        Octopus.PlaylistScheduler,
        Octopus.KioskModeManager,
        Octopus.Mixer,

        # WebApp
        {Finch, name: Octopus.Finch},
        Octopus.Presence,
        OctopusWeb.Endpoint,

        # OSC
        Octopus.Osc.Server
      ] ++
        case System.get_env("TELEGRAM_BOT_SECRET") do
          nil -> []
          telegram_bot_secret -> [{Octopus.TelegramBot, bot_key: telegram_bot_secret}]
        end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Octopus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OctopusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
