defmodule Octopus.Apps.Starfield do
  @moduledoc """
  This app draws a randomly scrolling starfield with a parallax effect.
  """

  use Octopus.App, category: :animation

  alias Octopus.Canvas

  # Get the installation module for direct function calls
  @installation Octopus.installation()

  defmodule State do
    defstruct [:width, :height, :stars, :canvas, :config, :speed, :rotation]
  end

  @frame_rate 60
  @frame_time_s 1 / @frame_rate
  @frame_time_ms trunc(1000 / @frame_rate)

  def name, do: "Starfield"

  def config_schema() do
    %{
      speed: {"Speed", :float, %{min: 1.0, max: 20.0, default: 10.0}},
      rotation: {"Rotation", :float, %{min: 0.0, max: 360.0, default: 90.0}}
    }
  end

  def get_config(state) do
    %{
      speed: state.speed,
      rotation: state.rotation
    }
  end

  def init(_) do
    # Get dynamic dimensions from installation metadata
    canvas_width = trunc(@installation.width())
    canvas_height = trunc(@installation.height())

    # Use larger virtual space for starfield effect
    virtual_width = canvas_width * 2
    virtual_height = canvas_height * 2

    config = config_schema() |> default_config()

    state = %State{
      stars: %{},
      width: virtual_width,
      height: virtual_height,
      canvas: Canvas.new(canvas_width, canvas_height),
      speed: config.speed,
      rotation: :rand.uniform(360) - 1
    }

    state = state |> generate_stars(2048)

    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, state}
  end

  def handle_config(%{speed: speed, rotation: rotation}, %State{} = state) do
    {:noreply, %State{state | speed: speed, rotation: rotation}}
  end

  def handle_info(:tick, %State{} = state) do
    state =
      state
      |> rotate()
      |> update_stars()
      |> update_canvas()
      |> broadcast_frame()

    {:noreply, state}
  end

  defp generate_stars(%State{stars: stars} = state, count) do
    stars =
      Enum.reduce(0..count, stars, fn _i, stars ->
        x = :rand.uniform(state.width) - 1
        y = :rand.uniform(state.height) - 1
        speed = :rand.uniform() * 0.75 + 0.25
        Map.put(stars, {x, y}, speed)
      end)

    %State{state | stars: stars}
  end

  defp rotate(%State{} = state) do
    {seconds, micros} = Time.utc_now() |> Time.to_seconds_after_midnight()
    seconds = seconds + micros / 1_000_000

    rotation = fmod(seconds * 10, 360)

    %State{state | rotation: rotation}
  end

  defp update_stars(%State{stars: stars} = state) do
    stars =
      stars
      |> Enum.map(fn {{x, y}, speed} ->
        dx = :math.cos(state.rotation * :math.pi() / 180.0)
        dy = :math.sin(state.rotation * :math.pi() / 180.0)
        x = fmod(x + dx * speed * state.speed * @frame_time_s, state.width)
        y = fmod(y + dy * speed * state.speed * @frame_time_s, state.height)
        {{x, y}, speed}
      end)
      |> Map.new()

    %State{state | stars: stars}
  end

  defp update_canvas(%State{canvas: canvas, stars: stars} = state) do
    canvas = canvas |> Canvas.clear()

    # Get canvas dimensions for clipping
    canvas_width = canvas.width
    canvas_height = canvas.height

    canvas =
      stars
      |> Enum.sort_by(fn {_, speed} -> speed end)
      |> Enum.reduce(canvas, fn {{x, y}, speed}, canvas ->
        # Only draw stars that are within the canvas bounds
        pixel_x = trunc(x)
        pixel_y = trunc(y)

        if pixel_x >= 0 and pixel_x < canvas_width and pixel_y >= 0 and pixel_y < canvas_height do
          color_value = speed * 255
          color = {trunc(color_value * 0.8), trunc(color_value * 0.9), trunc(color_value)}
          canvas |> Canvas.put_pixel({pixel_x, pixel_y}, color)
        else
          canvas
        end
      end)

    %State{state | canvas: canvas}
  end

  defp broadcast_frame(%State{canvas: canvas} = state) do
    canvas |> Canvas.to_frame(drop: true) |> send_frame()
    state
  end

  defp fmod(dividend, divisor) do
    quotient = floor(dividend / divisor)
    dividend - quotient * divisor
  end
end
