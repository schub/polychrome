defmodule Octopus.Installation.Nation2025 do
  @behaviour Octopus.Installation

  @panel_height 8
  @panel_width 8
  @panel_gap 16
  @num_panels 12
  @num_buttons 12

  # Simulator layout constants
  @sim_pixel_width 8
  @sim_pixel_height 8
  @sim_image_width 3463
  @sim_image_height 1469
  @sim_offset_x 600
  @sim_offset_y 1100
  @sim_spacing 128

  @num_panels 12

  @impl true
  def num_panels() do
    @num_panels
  end

  @impl true
  def num_buttons() do
    @num_buttons
  end

  @impl true
  def panel_offsets() do
    # Calculate panel spacing in virtual pixels for circular arrangement
    panel_spacing_pixels = calculate_panel_spacing_pixels()

    # Generate linear panel positions on a plane
    for i <- 0..(@num_panels - 1) do
      {i * panel_spacing_pixels, 0}
    end
  end

  def calculate_panel_spacing_pixels() do
    diameter_in_meters = Octopus.Params.Sim3d.diameter()
    radius_in_meters = diameter_in_meters / 2
    panel_width_in_meters = 1.6
    angle_between_panels = 2 * :math.pi() / @num_panels
    pixels_per_meter = 8 / panel_width_in_meters

    chord_length_pixels =
      2 * (radius_in_meters * pixels_per_meter) * :math.sin(angle_between_panels / 2)

    round(chord_length_pixels)
  end

  @impl true
  def panel_count() do
    @num_panels
  end

  @impl true
  def panel_width() do
    @panel_width
  end

  @impl true
  def panel_height() do
    @panel_height
  end

  @impl true
  def panel_gap() do
    @panel_gap
  end

  @impl true
  def center_x() do
    width() / 2 - 0.5
  end

  @impl true
  def center_y() do
    height() / 2 - 0.5
  end

  @impl true
  def width() do
    {min_x, max_x} = panels() |> List.flatten() |> Enum.map(fn {x, _y} -> x end) |> Enum.min_max()
    max_x - min_x + 1
  end

  @impl true
  def height() do
    {min_y, max_y} = panels() |> List.flatten() |> Enum.map(fn {_x, y} -> y end) |> Enum.min_max()
    max_y - min_y + 1
  end

  @impl true
  def panels() do
    for {offset_x, offset_y} <- panel_offsets() do
      for y <- 0..(@panel_height - 1), x <- 0..(@panel_width - 1) do
        {
          x + offset_x,
          y + offset_y
        }
      end
    end
  end

  @impl true
  def simulator_layouts() do
    positions =
      for i <- 0..(@num_panels - 1), y <- 0..(@panel_height - 1), x <- 0..(@panel_width - 1) do
        {
          @sim_offset_x + i * (@sim_spacing + @sim_pixel_width * @panel_width) +
            x * @sim_pixel_width,
          @sim_offset_y + y * @sim_pixel_height
        }
      end

    [
      %Octopus.Layout{
        name: "Nation 2025",
        positions: positions,
        # Width should match the logical canvas width (including gaps)
        width: (@num_panels - 1) * (@panel_width + @panel_gap) + @panel_width,
        height: @panel_height,
        pixel_size: {@sim_pixel_width, @sim_pixel_height},
        pixel_margin: {0, 0, 0, 0},
        background_image: "/images/nation2025-background.webp",
        pixel_image: "/images/nation2025-overlay.webp",
        image_size: {@sim_image_width, @sim_image_height}
      }
    ]
  end
end
