defmodule OctopusWeb.ProximityLive do
  use OctopusWeb, :live_view

  @batch_size 3

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Octopus.ProximitySensor.subscribe()
    end

    socket =
      assign(socket,
        buffer: %{}
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:reading, sensor_key, distance, timestamp}, socket) do
    socket =
      case sensor_key do
        {1, 0} = {panel, index} ->
          add_to_buffer(socket, "sensor_#{panel}_#{index}", distance, timestamp)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp add_to_buffer(socket, sensor_key, distance, timestamp) do
    current_buffer = Map.get(socket.assigns.buffer, sensor_key, [])

    new_reading = %{distance: distance, timestamp: timestamp}
    updated_buffer = [new_reading | current_buffer]

    if length(updated_buffer) >= @batch_size do
      readings = Enum.reverse(updated_buffer)

      socket
      |> push_event("proximity-data", %{sensor: sensor_key, readings: readings})
      |> assign(buffer: Map.delete(socket.assigns.buffer, sensor_key))
    else
      assign(socket, buffer: Map.put(socket.assigns.buffer, sensor_key, updated_buffer))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full p-4">
      <div class="bg-white shadow rounded-lg p-4">
        <h1 class="text-2xl font-bold mb-4">Proximity Readings</h1>
        <div class="w-full h-96">
          <canvas id="proximity-chart" phx-hook="ProximityChart" class="w-full h-full"></canvas>
        </div>
      </div>
    </div>
    """
  end
end
