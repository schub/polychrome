defmodule Octopus.Apps.StaticImage do
  alias Octopus.Protobuf.ControlEvent
  alias Octopus.WebP
  use Octopus.App, category: :animation

  def name, do: "Static Image"

  def config_schema do
    %{
      image: {"Static Image", :string, %{default: "polychrome_eventphone"}}
    }
  end

  def get_config(%{image: image}) do
    %{image: image}
  end

  def app_init(%{image: image}) do
    # Load image to determine appropriate layout
    loaded_image = WebP.load(image)

    # Configure layout based on image width (was Canvas.to_frame(drop: image.width > 80))
    layout =
      if loaded_image && loaded_image.width > 80, do: :gapped_panels, else: :adjacent_panels

    Octopus.App.configure_display(layout: layout)

    send(self(), :display)
    {:ok, %{image: image}}
  end

  def handle_config(%{image: image}, state) do
    state = %{state | image: image}
    display(state)
    {:noreply, state}
  end

  def handle_control_event(%ControlEvent{type: type}, state)
      when type in [:APP_SELECTED, :APP_STARTED] do
    display(state)
    {:noreply, state}
  end

  def handle_control_event(_, state) do
    {:noreply, state}
  end

  def handle_info(:display, state) do
    display(state)
    {:noreply, state}
  end

  def display(%{image: image}) do
    case WebP.load(image) do
      nil -> nil
      # Use new unified display API instead of Canvas.to_frame() |> send_frame()
      image -> Octopus.App.update_display(image)
    end
  end
end
