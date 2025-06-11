defmodule Octopus.Installation.Nation2024 do
  @behaviour Octopus.Installation

  @panel_height 8
  @panel_width 8
  @panel_distance 25
  @num_panels 10

  @panels_offsets for i <- 0..(@num_panels - 1), do: {@panel_distance * i, 0}

  # Simulator layout constants for 10 panels
  @sim_pixel_width 25
  @sim_pixel_height 25
  @sim_image_width 12900
  @sim_image_height 5470
  @sim_offset_x 1750
  @sim_offset_y 3750
  @sim_spacing 800

  @impl true
  def panel_offsets() do
    @panels_offsets
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
    for {offset_x, offset_y} <- @panels_offsets do
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
        name: "Nation 2024",
        positions: positions,
        # Dynamic sizing based on constants
        width: @panel_width * @num_panels,
        height: @panel_height,
        pixel_size: {@sim_pixel_width, @sim_pixel_height},
        pixel_margin: {0, 0, 0, 0},
        background_image: "/images/nation.webp",
        pixel_image: "/images/mildenberg-pixel-overlay.webp",
        image_size: {@sim_image_width, @sim_image_height}
      }
    ]
  end
end
