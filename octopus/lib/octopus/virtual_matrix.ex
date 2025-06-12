defmodule Octopus.VirtualMatrix do
  @moduledoc """
  Provides an abstraction for managing virtual matrices that span multiple panels.

  This module handles the complexity of panel layouts, coordinate transformations,
  and automatic frame distribution to physical panels.
  """

  alias Octopus.Canvas

  defstruct [:width, :height, :panels, :layout_type, :installation]

  @type layout_type :: :linear | :circular
  @type panel_mapping :: %{integer() => {integer(), integer(), integer(), integer()}}
  @type t :: %__MODULE__{
          width: integer(),
          height: integer(),
          panels: panel_mapping(),
          layout_type: layout_type(),
          installation: module()
        }

  @doc """
  Creates a new virtual matrix for the given installation.

  Options:
  - `:layout` - Layout type (:linear, :circular). Default: :linear
  - `:circular_gap` - Whether to add gap after last panel in circular layout. Default: true
  """
  @spec new(module(), keyword()) :: t()
  def new(installation, opts \\ []) do
    layout_type = Keyword.get(opts, :layout, :linear)
    circular_gap = Keyword.get(opts, :circular_gap, true)

    %__MODULE__{
      installation: installation,
      layout_type: layout_type,
      width: calculate_width(installation, layout_type, circular_gap),
      height: calculate_height(installation, layout_type),
      panels: build_panel_mapping(installation, layout_type, circular_gap)
    }
  end

  @doc """
  Renders a canvas to individual panel frames and returns the combined frame.

  Takes a canvas that represents the entire virtual matrix and automatically
  cuts it into the appropriate panel sections, then joins them for transmission.
  """
  @spec render_frame(t(), Canvas.t()) :: Canvas.t()
  def render_frame(%__MODULE__{} = matrix, canvas) do
    panel_width = matrix.installation.panel_width()
    panel_height = matrix.installation.panel_height()

    matrix.installation.panel_offsets()
    |> Enum.map(fn {x_offset, y_offset} ->
      Canvas.cut(
        canvas,
        {x_offset, y_offset},
        {x_offset + panel_width - 1, y_offset + panel_height - 1}
      )
    end)
    |> Enum.reverse()
    |> Enum.reduce(&Canvas.join/2)
  end

  @doc """
  Converts global virtual matrix coordinates to panel-local coordinates.

  Returns `{panel_id, local_x, local_y}` or `:not_found` if coordinates
  don't fall within any panel.
  """
  @spec global_to_panel_coords(t(), integer(), integer()) ::
          {integer(), integer(), integer()} | :not_found
  def global_to_panel_coords(%__MODULE__{} = matrix, global_x, global_y) do
    panel_width = matrix.installation.panel_width()
    panel_height = matrix.installation.panel_height()

    matrix.installation.panel_offsets()
    |> Enum.with_index()
    |> Enum.find_value(:not_found, fn {{x_offset, y_offset}, panel_id} ->
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
    panel_offsets = matrix.installation.panel_offsets()

    if panel_id >= 0 and panel_id < length(panel_offsets) do
      {x_offset, y_offset} = Enum.at(panel_offsets, panel_id)
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

  defp calculate_width(installation, :linear, _circular_gap) do
    panel_width = installation.panel_width()
    panel_gap = installation.panel_gap()
    num_panels = installation.panel_count()
    (panel_width + panel_gap) * num_panels
  end

  defp calculate_width(installation, :circular, circular_gap) do
    panel_width = installation.panel_width()
    panel_gap = installation.panel_gap()
    num_panels = installation.panel_count()

    base_width = (panel_width + panel_gap) * num_panels

    if circular_gap do
      base_width
    else
      base_width - panel_gap
    end
  end

  defp calculate_height(installation, layout_type) when layout_type in [:linear, :circular] do
    installation.panel_height()
  end

  defp build_panel_mapping(installation, :linear, _circular_gap) do
    panel_width = installation.panel_width()
    panel_height = installation.panel_height()

    installation.panel_offsets()
    |> Enum.with_index()
    |> Enum.into(%{}, fn {{x_offset, y_offset}, panel_id} ->
      {panel_id, {x_offset, y_offset, panel_width, panel_height}}
    end)
  end

  defp build_panel_mapping(installation, :circular, circular_gap) do
    # For now, circular layout is the same as linear
    # In the future, this could arrange panels in an actual circle
    build_panel_mapping(installation, :linear, circular_gap)
  end
end
