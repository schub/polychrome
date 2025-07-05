defmodule Octopus.Installation do
  @typedoc """
  Logical position of a pixel in the installation
  """
  @type pixel :: {integer(), integer()}

  @typedoc """
  Physical layout of the installation
  """
  @type layout :: :circular | :linear

  @callback num_panels() :: pos_integer()

  @callback panel_width() :: integer()
  @callback panel_height() :: integer()
  @callback panel_gap() :: integer()

  @callback width() :: integer()
  @callback height() :: integer()

  @callback center_x() :: number()
  @callback center_y() :: number()

  @callback simulator_layouts() :: nonempty_list(Octopus.Layout.t())

  @doc """
  Returns the number of buttons available in this installation
  """
  @callback num_buttons() :: pos_integer()

  @options_schema NimbleOptions.new!(
                    num_panels: [type: :pos_integer, required: true],
                    num_buttons: [type: :non_neg_integer, required: true],
                    panel_width: [type: :pos_integer, required: true],
                    panel_height: [type: :pos_integer, required: true],
                    panel_gap: [type: :pos_integer, required: true],
                    width: [type: :pos_integer, required: true],
                    height: [type: :pos_integer, required: true],
                    simulator_layouts: [
                      type:
                        {:list,
                         {:keyword_list,
                          [
                            name: [type: :string, required: true],
                            background_image: [type: :string, required: true],
                            pixel_image: [type: :string, required: true],
                            image_size: [
                              type: {:tuple, [:pos_integer, :pos_integer]},
                              required: true
                            ],
                            pixel_size: [
                              type: {:tuple, [:pos_integer, :pos_integer]},
                              required: true
                            ],
                            offset_x: [type: :non_neg_integer, required: true],
                            offset_y: [type: :non_neg_integer, required: true],
                            spacing: [type: :non_neg_integer, required: true]
                          ]}}
                    ]
                  )

  @moduledoc """
  Defines an installation.

  An installation is a collection of panels and buttons.

  The installation is responsible for:

  Supported options:\n#{NimbleOptions.docs(@options_schema)}
  """

  defmacro __using__(opts) do
    opts = NimbleOptions.validate!(opts, @options_schema)

    num_panels = Keyword.fetch!(opts, :num_panels)
    num_buttons = Keyword.fetch!(opts, :num_buttons)
    panel_width = Keyword.fetch!(opts, :panel_width)
    panel_height = Keyword.fetch!(opts, :panel_height)
    panel_gap = Keyword.fetch!(opts, :panel_gap)
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    simulator_layouts =
      Keyword.fetch!(opts, :simulator_layouts)
      |> Enum.map(fn opts ->
        name = Keyword.fetch!(opts, :name)
        offset_x = Keyword.fetch!(opts, :offset_x)
        offset_y = Keyword.fetch!(opts, :offset_y)
        spacing = Keyword.fetch!(opts, :spacing)
        {pixel_width, pixel_height} = Keyword.fetch!(opts, :pixel_size)
        {image_width, image_height} = Keyword.fetch!(opts, :image_size)
        background_image = Keyword.fetch!(opts, :background_image)
        pixel_image = Keyword.fetch!(opts, :pixel_image)

        positions =
          for i <- 0..(num_panels - 1),
              y <- 0..(panel_height - 1),
              x <- 0..(panel_width - 1) do
            {
              offset_x + i * (spacing + pixel_width * panel_width) + x * pixel_width,
              offset_y + y * pixel_height
            }
          end

        %Octopus.Layout{
          name: name,
          positions: positions,
          # Width should match the logical canvas width (including gaps)
          width: (num_panels - 1) * (panel_width + panel_gap) + panel_width,
          height: panel_height,
          pixel_size: {pixel_width, pixel_height},
          pixel_margin: {0, 0, 0, 0},
          background_image: background_image,
          pixel_image: pixel_image,
          image_size: {image_width, image_height}
        }
      end)
      |> Macro.escape()

    quote do
      @behaviour Octopus.Installation

      @impl Octopus.Installation
      def num_panels(), do: unquote(num_panels)
      @impl Octopus.Installation
      def num_buttons(), do: unquote(num_buttons)
      @impl Octopus.Installation
      def panel_width(), do: unquote(panel_width)
      @impl Octopus.Installation
      def panel_height(), do: unquote(panel_height)
      @impl Octopus.Installation
      def panel_gap(), do: unquote(panel_gap)
      @impl Octopus.Installation
      def width(), do: unquote(width)
      @impl Octopus.Installation
      def height(), do: unquote(height)
      @impl Octopus.Installation
      def center_x(), do: width() / 2 - 0.5
      @impl Octopus.Installation
      def center_y(), do: height() / 2 - 0.5
      @impl Octopus.Installation
      def simulator_layouts(), do: unquote(simulator_layouts)
    end
  end

  @behaviour __MODULE__

  @impl __MODULE__
  defdelegate num_panels, to: Application.compile_env(:octopus, :installation)
  @deprecated "Use num_panels/0 instead"
  defdelegate panel_count, as: :num_panels, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate panel_width, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate panel_height, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate panel_gap, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate width, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate height, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate center_x, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate center_y, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate simulator_layouts, to: Application.compile_env(:octopus, :installation)
  @impl __MODULE__
  defdelegate num_buttons, to: Application.compile_env(:octopus, :installation)

  def panels() do
    for {offset_x, offset_y} <- panel_offsets() do
      for y <- 0..(panel_height() - 1), x <- 0..(panel_width() - 1) do
        {
          x + offset_x,
          y + offset_y
        }
      end
    end
  end

  def panel_offsets() do
    # Calculate panel spacing in virtual pixels for circular arrangement
    panel_spacing_pixels = calculate_panel_spacing_pixels()

    # Generate linear panel positions on a plane
    for i <- 0..(num_panels() - 1) do
      {i * panel_spacing_pixels, 0}
    end
  end

  defp calculate_panel_spacing_pixels() do
    diameter_in_meters = Octopus.Params.Sim3d.diameter()
    radius_in_meters = diameter_in_meters / 2
    panel_width_in_meters = 1.6
    angle_between_panels = 2 * :math.pi() / num_panels()
    pixels_per_meter = 8 / panel_width_in_meters

    chord_length_pixels =
      2 * (radius_in_meters * pixels_per_meter) * :math.sin(angle_between_panels / 2)

    round(chord_length_pixels)
  end
end
