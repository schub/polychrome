defmodule OctopusWeb.PixelsLive do
  use OctopusWeb, :live_view

  import Phoenix.LiveView, only: [push_event: 3, connected?: 1]

  alias Octopus.ColorPalette
  alias Octopus.Mixer
  alias Octopus.Protobuf.{FirmwareConfig, Frame, InputEvent}

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "pixels"

  defp get_views() do
    [default_layout | _] = Octopus.installation().simulator_layouts()

    %{
      "default" => default_layout
    }
  end

  @default_view "default"

  defp get_button_atom(index) do
    # Use existing atoms from protobuf schema
    case index do
      1 -> :BUTTON_1
      2 -> :BUTTON_2
      3 -> :BUTTON_3
      4 -> :BUTTON_4
      5 -> :BUTTON_5
      6 -> :BUTTON_6
      7 -> :BUTTON_7
      8 -> :BUTTON_8
      9 -> :BUTTON_9
      10 -> :BUTTON_10
      11 -> :BUTTON_11
      12 -> :BUTTON_12
      _ -> nil
    end
  end

  defp get_key_map() do
    num_buttons = Octopus.installation().num_buttons()

    # Base button mappings for number keys and function keys
    button_mappings =
      for i <- 1..min(num_buttons, 10), button = get_button_atom(i), not is_nil(button) do
        key = if i == 10, do: "0", else: to_string(i)
        {key, button}
      end ++
        for i <- 1..min(num_buttons, 12), button = get_button_atom(i), not is_nil(button) do
          key = "F#{i}"
          {key, button}
        end

    # Additional mappings for joystick and menu
    additional_mappings = [
      {"w", :DIRECTION_1_UP},
      {"a", :DIRECTION_1_LEFT},
      {"s", :DIRECTION_1_DOWN},
      {"d", :DIRECTION_1_RIGHT},
      {"q", :BUTTON_A_1},
      {"i", :DIRECTION_2_UP},
      {"j", :DIRECTION_2_LEFT},
      {"k", :DIRECTION_2_DOWN},
      {"l", :DIRECTION_2_RIGHT},
      {"u", :BUTTON_A_2},
      {"m", :BUTTON_MENU}
    ]

    (button_mappings ++ additional_mappings) |> Enum.into(%{})
  end

  def mount(_params, _session, socket) do
    views = get_views()
    pixel_layout = views[@default_view]

    socket =
      if connected?(socket) do
        Mixer.subscribe()

        frame = %Frame{
          data: List.duplicate(0, pixel_layout.width * pixel_layout.height),
          palette: ColorPalette.load("pico-8")
        }

        socket
        |> push_layout(views[@default_view])
        |> push_config(@default_config)
        |> push_frame(frame)
        |> push_pixel_offset(0)
      else
        socket
      end

    view_options = Enum.map(views, fn {k, v} -> [key: v.name, value: k] end)
    max_windows = length(Octopus.installation().panels())
    num_buttons = Octopus.installation().num_buttons()

    {:ok,
     socket
     |> assign(
       id: socket.id,
       id_prefix: @id_prefix,
       pixel_layout: views[@default_view],
       view: @default_view,
       view_options: view_options,
       views: views,
       max_windows: max_windows,
       window: 1,
       num_buttons: num_buttons,
       key_map: get_key_map(),
       pressed_buttons: MapSet.new()
     )}
  end

  def render(assigns) do
    ~H"""
    <div
      class="flex w-full h-full justify-center bg-black"
      phx-window-keydown="keydown"
      phx-window-keyup="keyup"
    >
      <div class="absolute top-4 flex flex-col gap-3 z-10">
        <!-- Playlist Information -->
        <form id="view-form" phx-change="view-changed">
          <.input type="select" name="view" options={@view_options} value={@view} />
        </form>
        <div :if={@view != "default"}>
          <button
            :for={window <- 1..@max_windows}
            phx-click="window-changed"
            phx-value-window={window}
            class={[
              if(@window == window, do: "bg-neutral-100/20", else: "bg-neutral-900/20"),
              "text-neutral-100 rounded inline-block mx-1 w-6 border border-neutral-500 shadow text-center"
            ]}
          >
            {window}
          </button>
        </div>
      </div>

      <div class="w-full h-full float-left relative">
        <canvas
          id={"#{@id_prefix}-#{@id}"}
          phx-hook="Pixels"
          class="w-full h-full bg-contain bg-no-repeat bg-center"
          style={"background-image: url(#{@pixel_layout.background_image});"}
        />
        <%!-- <img
          src={@pixel_layout.pixel_image}
          class="absolute left-0 top-0 w-full h-full object-contain mix-blend-multiply pointer-events-none"
        /> --%>

        <!-- Button UI Panel - Bottom -->
        <div class="absolute bottom-4 left-1/2 transform -translate-x-1/2 z-10">
          <div class="flex gap-2 justify-center">
            <button
              :for={i <- 1..@num_buttons}
              phx-click="button-click"
              phx-value-button={i}
              class={[
                "rounded px-3 py-2 text-sm font-mono border shadow transition-colors select-none min-w-[2.5rem] cursor-pointer",
                case get_button_atom(i) do
                  nil -> "bg-neutral-700 hover:bg-neutral-600 active:bg-neutral-500 text-neutral-100 border-neutral-500"
                  button_atom ->
                    if MapSet.member?(@pressed_buttons, button_atom) do
                      "bg-green-600 hover:bg-green-500 border-green-400 text-white"
                    else
                      "bg-neutral-700 hover:bg-neutral-600 active:bg-neutral-500 text-neutral-100 border-neutral-500"
                    end
                end
              ]}
              type="button"
            >
              {i}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("view-changed", %{"view" => view}, socket) do
    views = socket.assigns.views
    view = if Map.has_key?(views, view), do: view, else: @default_view
    pixel_layout = Map.get(views, view)

    socket =
      socket
      |> push_layout(pixel_layout)
      |> push_pixel_offset(0)
      |> assign(view: view, pixel_layout: pixel_layout)

    {:noreply, socket}
  end

  def handle_event("window-changed", %{"window" => window_string}, socket) do
    {window, pixel_offset} =
      case socket.assigns.view do
        "default" ->
          {1, 0}

        _ ->
          {window, _} = Integer.parse(window_string)
          max_windows = socket.assigns.max_windows
          window = max(1, min(max_windows, window))
          {window, (window - 1) * 64}
      end

    socket =
      socket
      |> push_pixel_offset(pixel_offset)
      |> assign(window: window)

    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    key_map = socket.assigns.key_map

    if Map.has_key?(key_map, key) do
      button = key_map[key]

      {button, value} =
        case button do
          :DIRECTION_1_LEFT -> {:AXIS_X_1, -1}
          :DIRECTION_1_RIGHT -> {:AXIS_X_1, 1}
          :DIRECTION_1_DOWN -> {:AXIS_Y_1, 1}
          :DIRECTION_1_UP -> {:AXIS_Y_1, -1}
          :DIRECTION_2_LEFT -> {:AXIS_X_2, -1}
          :DIRECTION_2_RIGHT -> {:AXIS_X_2, 1}
          :DIRECTION_2_DOWN -> {:AXIS_Y_2, 1}
          :DIRECTION_2_UP -> {:AXIS_Y_2, -1}
          _ -> {button, 1}
        end

      # Update visual state for button presses (not directional keys)
      socket =
        case button do
          button
          when button in [
                 :BUTTON_1,
                 :BUTTON_2,
                 :BUTTON_3,
                 :BUTTON_4,
                 :BUTTON_5,
                 :BUTTON_6,
                 :BUTTON_7,
                 :BUTTON_8,
                 :BUTTON_9,
                 :BUTTON_10,
                 :BUTTON_11,
                 :BUTTON_12
               ] ->
            socket |> assign(pressed_buttons: MapSet.put(socket.assigns.pressed_buttons, button))

          _ ->
            socket
        end

      %InputEvent{type: button, value: value}
      |> Mixer.handle_event()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    key_map = socket.assigns.key_map

    if Map.has_key?(key_map, key) do
      button = key_map[key]

      {button, _} =
        case button do
          :DIRECTION_1_LEFT -> {:AXIS_X_1, 0}
          :DIRECTION_1_RIGHT -> {:AXIS_X_1, 0}
          :DIRECTION_1_UP -> {:AXIS_Y_1, 0}
          :DIRECTION_1_DOWN -> {:AXIS_Y_1, 0}
          :DIRECTION_2_LEFT -> {:AXIS_X_2, 0}
          :DIRECTION_2_RIGHT -> {:AXIS_X_2, 0}
          :DIRECTION_2_UP -> {:AXIS_Y_2, 0}
          :DIRECTION_2_DOWN -> {:AXIS_Y_2, 0}
          _ -> {button, 0}
        end

      # Update visual state for button releases (not directional keys)
      socket =
        case button do
          button
          when button in [
                 :BUTTON_1,
                 :BUTTON_2,
                 :BUTTON_3,
                 :BUTTON_4,
                 :BUTTON_5,
                 :BUTTON_6,
                 :BUTTON_7,
                 :BUTTON_8,
                 :BUTTON_9,
                 :BUTTON_10,
                 :BUTTON_11,
                 :BUTTON_12
               ] ->
            socket
            |> assign(pressed_buttons: MapSet.delete(socket.assigns.pressed_buttons, button))

          _ ->
            socket
        end

      %InputEvent{type: button, value: 0}
      |> Mixer.handle_event()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("button-click", %{"button" => button_string}, socket) do
    {button_index, _} = Integer.parse(button_string)

    case get_button_atom(button_index) do
      nil ->
        {:noreply, socket}

      button_atom ->
        # Update visual state - add to pressed buttons
        socket =
          socket
          |> assign(pressed_buttons: MapSet.put(socket.assigns.pressed_buttons, button_atom))

        # Send button press event
        %InputEvent{type: button_atom, value: 1}
        |> Mixer.handle_event()

        # Send button release event after a short delay to simulate a button press
        Process.send_after(self(), {:button_release, button_atom}, 100)

        {:noreply, socket}
    end
  end

  def handle_info({:button_release, button_atom}, socket) do
    # Update visual state - remove from pressed buttons
    socket =
      socket
      |> assign(pressed_buttons: MapSet.delete(socket.assigns.pressed_buttons, button_atom))

    %InputEvent{type: button_atom, value: 0}
    |> Mixer.handle_event()

    {:noreply, socket}
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> push_config(config)}
  end

  def handle_info({:mixer, _msg}, socket) do
    {:noreply, socket}
  end

  defp push_layout(socket, layout) do
    push_event(socket, "layout:#{@id_prefix}-#{socket.id}", %{layout: layout})
  end

  defp push_frame(socket, frame) do
    push_event(socket, "frame:#{@id_prefix}-#{socket.id}", %{frame: frame})
  end

  defp push_config(socket, config) do
    push_event(socket, "config:#{@id_prefix}-#{socket.id}", %{config: config})
  end

  defp push_pixel_offset(socket, offset) do
    push_event(socket, "pixel_offset:#{@id_prefix}-#{socket.id}", %{offset: offset})
  end
end
