defmodule Octopus.Installation.Nation2025 do
  @behaviour Octopus.Installation

  @panel_height 8
  @panel_width 8

  # Simulator layout constants
  @sim_pixel_width 8
  @sim_pixel_height 8
  @sim_image_width 3463
  @sim_image_height 1469
  @sim_offset_x 200
  @sim_offset_y 1100
  @sim_spacing 200

  @panels_offsets [
    {0, 0},
    {25 * 1, 0},
    {25 * 2, 0},
    {25 * 3, 0},
    {25 * 4, 0},
    {25 * 5, 0},
    {25 * 6, 0},
    {25 * 7, 0},
    {25 * 8, 0},
    {25 * 9, 0},
    {25 * 10, 0},
    {25 * 11, 0}
  ]

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
      for i <- 0..11, y <- 0..7, x <- 0..7 do
        {
          @sim_offset_x + i * (@sim_spacing + @sim_pixel_width * 8) + x * @sim_pixel_width,
          @sim_offset_y + y * @sim_pixel_height
        }
      end

    [
      %Octopus.Layout{
        name: "Nation 2025",
        positions: positions,
        # 12 panels × 8 pixels wide
        width: 8 * 12,
        # 8 pixels tall
        height: 8,
        pixel_size: {@sim_pixel_width, @sim_pixel_height},
        pixel_margin: {0, 0, 0, 0},
        background_image: "/images/nation2025-background.webp",
        pixel_image: "/images/nation2025-overlay.webp",
        image_size: {@sim_image_width, @sim_image_height}
      }
    ]
  end
end
