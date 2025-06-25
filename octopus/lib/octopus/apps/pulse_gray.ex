defmodule Octopus.Apps.PulseGray do
  use Octopus.App, category: :test

  alias Octopus.Canvas

  @fps 30
  @frame_time_ms trunc(1000 / @fps)

  def name, do: "Pulse Gray"

  def app_init(config) do
    # Configure display for grayscale output using the new API
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 50
    )

    # Start animation timer
    :timer.send_after(@frame_time_ms, :tick)

    {:ok, %{phase: 0.0, speed: Map.get(config, :speed, 0.5)}}
  end

  def handle_info(:tick, %{phase: phase, speed: speed} = state) do
    # Schedule next frame
    :timer.send_after(@frame_time_ms, :tick)

    # Get display dimensions
    display_info = Octopus.App.get_display_info()

    # Create pulsating intensity (0-255)
    intensity = :math.sin(phase) |> abs() |> Kernel.*(255) |> trunc()

    # Create grayscale canvas filled with current intensity
    canvas =
      Canvas.new(display_info.width, display_info.height, :grayscale)
      |> Canvas.fill(intensity)

    # Send grayscale canvas to mixer
    Octopus.App.update_display(canvas, :grayscale)

    # Update phase for next frame
    new_phase = phase + speed * 2 * :math.pi() / @fps
    {:noreply, %{state | phase: new_phase}}
  end

  def config_schema() do
    %{
      speed: {"Speed", :float, %{min: 0.1, max: 2.0, default: 0.5}}
    }
  end

  def get_config(%{speed: speed}) do
    %{speed: speed}
  end

  def handle_config(%{speed: speed}, state) do
    {:noreply, %{state | speed: speed}}
  end
end
