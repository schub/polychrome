defmodule Octopus.Installation.Nation2025 do
  use Octopus.Installation,
    num_panels: 12,
    num_buttons: 12,
    panel_width: 8,
    panel_height: 8,
    panel_gap: 16,
    width: 1280,
    height: 720,
    simulator_layouts: [
      [
        name: "Nation 2025",
        background_image: "/images/nation2025-background.webp",
        pixel_image: "/images/nation2025-overlay.webp",
        image_size: {3463, 1469},
        pixel_size: {8, 8},
        offset_x: 600,
        offset_y: 1100,
        spacing: 128
      ]
    ]
end
