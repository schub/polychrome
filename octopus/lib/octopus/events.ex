defmodule Octopus.Events do
  @moduledoc """
  Main interface for the event handling system.

  Events are routed through this module to appropriate handlers based on event type
  and system state. This module delegates to Events.Router for the actual routing logic.
  """

  alias Octopus.Events.Router

  @doc """
  Handle an incoming event by routing it to appropriate handlers.

  This is the main entry point for all events in the system.
  """
  def handle_event(event) do
    Router.route_event(event)
  end

  @doc """
  Subscribe to event-related topics for debugging or monitoring.
  """
  def subscribe do
    Router.subscribe()
  end
end
