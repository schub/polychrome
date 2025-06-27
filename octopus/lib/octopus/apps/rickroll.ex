defmodule Octopus.Apps.Rickroll do
  use Octopus.App, category: :animation

  alias Octopus.WebP
  alias Octopus.Protobuf.AudioFrame
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  require Logger

  def name, do: "Rickroll"

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    animation = WebP.load_animation("rickroll-fullwidth")
    send(self(), :tick)
    {:ok, %{animation: animation, index: 0}}
  end

  def handle_info(:tick, %{animation: animation, index: index} = state) do
    {canvas, duration} = Enum.at(animation, index)
    Octopus.App.update_display(canvas)
    index = rem(index + 1, length(animation))
    Process.send_after(self(), :tick, duration)
    {:noreply, %{state | index: index}}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    num_buttons = Octopus.installation().num_buttons()

    1..num_buttons
    |> Enum.map(&%AudioFrame{uri: "file://rickroll.wav", stop: false, channel: &1})
    |> Enum.each(&send_frame/1)

    {:noreply, state}
  end

  def handle_event(_, state) do
    {:noreply, state}
  end
end
