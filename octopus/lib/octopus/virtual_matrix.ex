defmodule Octopus.VirtualMatrix do
  @moduledoc """
  Provides an abstraction for managing virtual matrices that span multiple panels.

  This module handles the complexity of panel layouts, coordinate transformations,
  and automatic frame distribution to physical panels.
  """

  alias Octopus.Canvas

  defstruct [:width, :height, :layout_type, :installation]

  @type layout_type :: :adjacent_panels | :gapped_panels | :gapped_panels_wrapped
  @type t :: %__MODULE__{
          width: integer(),
          height: integer(),
          layout_type: layout_type(),
          installation: module()
        }

  @doc """
  Creates a new virtual matrix for the given installation.

  Options:
  - `:layout` - Layout type (:adjacent_panels, :gapped_panels, :gapped_panels_wrapped). Default: :gapped_panels
  """
  @spec new(module(), keyword()) :: t()
  def new(installation, opts \\ []) do
    layout_type = Keyword.get(opts, :layout, :gapped_panels)

    %__MODULE__{
      installation: installation,
      layout_type: layout_type,
      width: calculate_width(installation, layout_type),
      height: installation.panel_height()
    }
  end

  @doc """
  Converts a virtual canvas to a frame, arranging it according to the physical panel layout.
  """
  @spec to_frame(t(), Canvas.t()) :: any()
  def to_frame(%__MODULE__{} = matrix, canvas) do
    {panel_width, panel_height, panel_count} = get_panel_dimensions(matrix)

    0..(panel_count - 1)
    |> Enum.map(fn panel_id ->
      {x_offset, y_offset} = panel_position(matrix, panel_id)

      Canvas.cut(
        canvas,
        {x_offset, y_offset},
        {x_offset + panel_width - 1, y_offset + panel_height - 1}
      )
    end)
    |> Enum.reverse()
    |> Enum.reduce(&Canvas.join/2)
    |> Canvas.to_frame()
  end

  @doc """
  Converts a virtual canvas to a frame and sends it using send_frame/1.
  """
  @spec send_frame(t(), Canvas.t()) :: :ok
  def send_frame(matrix, canvas) do
    matrix |> to_frame(canvas) |> Octopus.App.send_frame()
  end

  @doc """
  Converts global virtual matrix coordinates to panel-local coordinates.

  Returns `{panel_id, local_x, local_y}` or `:not_found` if coordinates
  don't fall within any panel.
  """
  @spec global_to_panel_coords(t(), integer(), integer()) ::
          {integer(), integer(), integer()} | :not_found
  def global_to_panel_coords(%__MODULE__{} = matrix, global_x, global_y) do
    {panel_width, panel_height, panel_count} = get_panel_dimensions(matrix)

    # Find which panel this coordinate falls into
    Enum.find_value(0..(panel_count - 1), :not_found, fn panel_id ->
      {x_offset, y_offset} = panel_position(matrix, panel_id)

      if global_x >= x_offset and global_x < x_offset + panel_width and
           global_y >= y_offset and global_y < y_offset + panel_height do
        {panel_id, global_x - x_offset, global_y - y_offset}
      end
    end)
  end

  @doc """
  Converts panel-local coordinates to global virtual matrix coordinates.

  Returns `{global_x, global_y}` or `:invalid_panel` if panel_id is invalid.
  """
  @spec panel_to_global_coords(t(), integer(), integer(), integer()) ::
          {integer(), integer()} | :invalid_panel
  def panel_to_global_coords(%__MODULE__{} = matrix, panel_id, local_x, local_y) do
    panel_count = matrix.installation.panel_count()

    if panel_id >= 0 and panel_id < panel_count do
      {x_offset, y_offset} = panel_position(matrix, panel_id)
      {x_offset + local_x, y_offset + local_y}
    else
      :invalid_panel
    end
  end

  @doc """
  Returns the center coordinates of the virtual matrix.
  """
  @spec center(t()) :: {float(), float()}
  def center(%__MODULE__{} = matrix) do
    {matrix.width / 2 - 0.5, matrix.height / 2 - 0.5}
  end

  # Private functions

  # Extract common panel dimensions to avoid repeated installation calls
  defp get_panel_dimensions(%__MODULE__{} = matrix) do
    installation = matrix.installation
    {installation.panel_width(), installation.panel_height(), installation.panel_count()}
  end

  # Calculate panel position - centralized logic
  defp panel_position(%__MODULE__{} = matrix, panel_id) do
    panel_width = matrix.installation.panel_width()
    panel_gap = matrix.installation.panel_gap()

    case matrix.layout_type do
      :adjacent_panels ->
        {panel_id * panel_width, 0}

      :gapped_panels ->
        {panel_id * (panel_width + panel_gap), 0}

      :gapped_panels_wrapped ->
        {panel_id * (panel_width + panel_gap), 0}
    end
  end

  defp calculate_width(installation, :adjacent_panels) do
    # Panels are directly adjacent, no gaps
    installation.panel_count() * installation.panel_width()
  end

  defp calculate_width(installation, :gapped_panels) do
    # Gaps only between panels, not after the last one
    num_panels = installation.panel_count()
    panel_width = installation.panel_width()
    panel_gap = installation.panel_gap()
    num_panels * panel_width + (num_panels - 1) * panel_gap
  end

  defp calculate_width(installation, :gapped_panels_wrapped) do
    # Gaps between panels AND after the last panel for wrapping
    num_panels = installation.panel_count()
    panel_width = installation.panel_width()
    panel_gap = installation.panel_gap()
    num_panels * (panel_width + panel_gap)
  end
end
