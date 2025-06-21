defmodule Octopus.Events.Router do
  @moduledoc """
  Central event router for the Octopus system.

  This module is responsible for routing events to appropriate handlers based on
  event type and system state. It replaces the event handling functionality that
  was previously in the Mixer module.
  """

  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, AppManager, KioskModeManager}
  alias Octopus.Events.Event.{Controller, Proximity}
  alias Octopus.Protobuf.SoundToLightControlEvent

  @pubsub_topic "events_router"

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Route an event to appropriate handlers.

  This is the main entry point for event routing.
  """
  def route_event(event) do
    GenServer.cast(__MODULE__, {:route_event, event})
  end

  @doc """
  Subscribe to events router topics for debugging or monitoring.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @pubsub_topic)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_cast({:route_event, %Controller{} = controller_event}, state) do
    # Route controller events to selected app and kiosk mode manager
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, controller_event)
    KioskModeManager.handle_input(controller_event)

    # Broadcast event for monitoring/debugging
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:events_router, {:controller_event, controller_event}}
    )

    {:noreply, state}
  end

  def handle_cast({:route_event, %SoundToLightControlEvent{} = stl_event}, state) do
    # Route sound-to-light events to selected app
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, stl_event)

    # Broadcast event for monitoring/debugging
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:events_router, {:stl_event, stl_event}}
    )

    {:noreply, state}
  end

  def handle_cast({:route_event, %Proximity{} = proximity_event}, state) do
    # Route proximity events to selected app
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, proximity_event)

    # Broadcast event for monitoring/debugging
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:events_router, {:proximity_event, proximity_event}}
    )

    {:noreply, state}
  end

  def handle_cast({:route_event, event}, state) do
    # Log unknown event types for debugging
    Logger.warning("#{__MODULE__}: Unknown event type received: #{inspect(event)}")

    {:noreply, state}
  end
end
