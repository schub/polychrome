defmodule Octopus.AppManager do
  @moduledoc """
  Centralized app lifecycle and selection management.

  Manages which apps are selected for different purposes (single app, dual-side apps)
  and handles app lifecycle events like APP_SELECTED/APP_DESELECTED notifications.

  This module extracts app management concerns from the Mixer, allowing the Mixer
  to focus purely on visual mixing and transitions.
  """

  use GenServer
  require Logger

  alias Octopus.AppSupervisor
  alias Octopus.Protobuf.ControlEvent

  @topic "app_manager"

  defmodule State do
    defstruct selected_app: nil,
              last_selected_app: nil
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Selects the app with the given `app_id`.
  """
  def select_app(app_id) do
    GenServer.cast(__MODULE__, {:select_app, app_id})
  end

  @doc """
  Selects the app for a specific side (for dual-side apps).
  """
  def select_app(app_id, side) when side in [:left, :right] do
    GenServer.cast(__MODULE__, {:select_app, app_id, side})
  end

  @doc """
  Returns the currently selected app.
  """
  def get_selected_app() do
    GenServer.call(__MODULE__, :get_selected_app)
  end

  @doc """
  Subscribes to app manager events.

  Published messages:
  * `{:app_manager, {:selected_app, app_id}}` - the selected app changed
  * `{:app_manager, {:app_lifecycle, app_id, :selected | :deselected}}` - app lifecycle events
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_call(:get_selected_app, _from, %State{selected_app: selected_app} = state) do
    {:reply, selected_app, state}
  end

  # Handle dual-side app selection (for games like Blocks, etc.)
  def handle_cast({:select_app, next_app_id, side}, %State{} = state) do
    selected_app =
      case {state.selected_app, side} do
        {{_, right}, :left} -> {next_app_id, right}
        {{left, _}, :right} -> {left, next_app_id}
        {_, :left} -> {next_app_id, nil}
        {_, :right} -> {nil, next_app_id}
      end

    state = %State{
      state
      | selected_app: selected_app,
        last_selected_app: state.selected_app
    }

    broadcast_selected_app(state)
    send_lifecycle_events(state)

    {:noreply, state}
  end

  # Handle single app selection
  def handle_cast({:select_app, next_app_id}, %State{} = state) do
    state = %State{
      state
      | selected_app: next_app_id,
        last_selected_app: state.selected_app
    }

    broadcast_selected_app(state)
    send_lifecycle_events(state)

    {:noreply, state}
  end

  # Broadcast app selection changes
  defp broadcast_selected_app(%State{} = state) do
    selected =
      case state.selected_app do
        # For dual-side apps, we don't broadcast a single selected app
        {_, _} -> nil
        app_id -> app_id
      end

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:app_manager, {:selected_app, selected}}
    )
  end

  # Send APP_SELECTED/APP_DESELECTED lifecycle events to apps
  defp send_lifecycle_events(%State{selected_app: {_, _}} = _state) do
    # For dual-side apps, we don't send lifecycle events
    # (This matches current Mixer behavior)
    :ok
  end

  defp send_lifecycle_events(%State{} = state) do
    # Send APP_SELECTED to the newly selected app
    if state.selected_app do
      AppSupervisor.send_event(state.selected_app, %ControlEvent{type: :APP_SELECTED})

      Phoenix.PubSub.broadcast(
        Octopus.PubSub,
        @topic,
        {:app_manager, {:app_lifecycle, state.selected_app, :selected}}
      )
    end

    # Send APP_DESELECTED to the previously selected app
    if state.last_selected_app && state.last_selected_app != state.selected_app do
      AppSupervisor.send_event(state.last_selected_app, %ControlEvent{type: :APP_DESELECTED})

      Phoenix.PubSub.broadcast(
        Octopus.PubSub,
        @topic,
        {:app_manager, {:app_lifecycle, state.last_selected_app, :deselected}}
      )
    end
  end
end
