defmodule Octopus.TimeAnimator do
  @moduledoc """
  Time-based animation system using normalized time values (0.0 to 1.0).

  This animator doesn't know about frames or networking - it only produces
  Canvas objects based on time values. Apps control their own FPS and timing.

  This follows modern game engine patterns where animations are time-based
  functions that can be evaluated at any point.
  """

  alias Octopus.Canvas

  @doc """
  Evaluates a transition animation at a specific time point.

  Parameters:
  - `from_canvas` - Starting canvas
  - `to_canvas` - Target canvas
  - `time` - Float between 0.0 (start) and 1.0 (end)
  - `transition_type` - Type of transition (:push, :slide, :cut)
  - `opts` - Additional options for the transition

  Returns the interpolated Canvas at the given time point.
  """
  def evaluate_transition(from_canvas, to_canvas, time, transition_type, opts \\ [])

  def evaluate_transition(from_canvas, to_canvas, time, :push, opts) do
    direction = Keyword.get(opts, :direction, :top)

    # Clamp time to [0.0, 1.0]
    time = max(0.0, min(1.0, time))

    case direction do
      :top -> push_vertical(from_canvas, to_canvas, time, :up)
      :bottom -> push_vertical(from_canvas, to_canvas, time, :down)
      :left -> push_horizontal(from_canvas, to_canvas, time, :left)
      :right -> push_horizontal(from_canvas, to_canvas, time, :right)
    end
  end

  def evaluate_transition(from_canvas, to_canvas, time, :slide, opts) do
    direction = Keyword.get(opts, :direction, :right)

    # Clamp time to [0.0, 1.0]
    time = max(0.0, min(1.0, time))

    case direction do
      :right -> slide_horizontal(from_canvas, to_canvas, time, :right)
      :left -> slide_horizontal(from_canvas, to_canvas, time, :left)
      :top -> slide_vertical(from_canvas, to_canvas, time, :up)
      :bottom -> slide_vertical(from_canvas, to_canvas, time, :down)
    end
  end

  def evaluate_transition(_from_canvas, to_canvas, time, :cut, _opts) do
    # Simple cut transition - instant switch at time >= 1.0
    if time >= 1.0 do
      to_canvas
    else
      Canvas.new(to_canvas.width, to_canvas.height)
    end
  end

  # Fallback for unknown transition types
  def evaluate_transition(_from_canvas, to_canvas, time, _unknown, _opts) do
    # Default to cut transition
    if time >= 1.0, do: to_canvas, else: Canvas.new(to_canvas.width, to_canvas.height)
  end

  @doc """
  Creates an eased time value using common easing functions.

  Parameters:
  - `time` - Linear time value (0.0 to 1.0)
  - `easing` - Easing function type

  Returns the eased time value.
  """
  def ease(time, easing_type \\ :linear)

  def ease(time, :linear), do: time

  def ease(time, :ease_in_quad), do: time * time

  def ease(time, :ease_out_quad), do: 1 - (1 - time) * (1 - time)

  def ease(time, :ease_in_out_quad) do
    if time < 0.5 do
      2 * time * time
    else
      1 - 2 * (1 - time) * (1 - time)
    end
  end

  def ease(time, :ease_in_cubic), do: time * time * time

  def ease(time, :ease_out_cubic) do
    1 - (1 - time) * (1 - time) * (1 - time)
  end

  def ease(time, :ease_in_out_cubic) do
    if time < 0.5 do
      4 * time * time * time
    else
      1 - 4 * (1 - time) * (1 - time) * (1 - time)
    end
  end

  # Private helper functions for push transitions

  defp push_vertical(from_canvas, to_canvas, time, direction) do
    height = from_canvas.height
    # Fixed separation for now
    separation = 3

    # Calculate offset based on time
    total_distance = height + separation
    offset = round(time * total_distance)

    base_canvas = Canvas.new(from_canvas.width, height)

    case direction do
      :up ->
        # From canvas moves up (out the top)
        canvas_with_from =
          if offset < height do
            from_part = Canvas.cut(from_canvas, {0, offset}, {from_canvas.width - 1, height - 1})
            Canvas.overlay(base_canvas, from_part, offset: {0, 0})
          else
            base_canvas
          end

        # To canvas comes from bottom
        to_start_y = height + separation - offset

        if to_start_y < height and to_start_y >= 0 do
          to_height_visible = min(height - to_start_y, to_canvas.height)

          if to_height_visible > 0 do
            to_part = Canvas.cut(to_canvas, {0, 0}, {to_canvas.width - 1, to_height_visible - 1})
            Canvas.overlay(canvas_with_from, to_part, offset: {0, to_start_y})
          else
            canvas_with_from
          end
        else
          canvas_with_from
        end

      :down ->
        # From canvas moves down (out the bottom)
        canvas_with_from =
          if offset < height do
            from_height_visible = height - offset

            if from_height_visible > 0 do
              from_part =
                Canvas.cut(from_canvas, {0, 0}, {from_canvas.width - 1, from_height_visible - 1})

              Canvas.overlay(base_canvas, from_part, offset: {0, offset})
            else
              base_canvas
            end
          else
            base_canvas
          end

        # To canvas comes from top
        to_end_y = offset - separation - 1

        if to_end_y >= 0 do
          to_height_visible = min(to_end_y + 1, to_canvas.height)

          if to_height_visible > 0 do
            to_source_start_y = max(0, to_canvas.height - to_height_visible)

            to_part =
              Canvas.cut(
                to_canvas,
                {0, to_source_start_y},
                {to_canvas.width - 1, to_canvas.height - 1}
              )

            Canvas.overlay(canvas_with_from, to_part, offset: {0, 0})
          else
            canvas_with_from
          end
        else
          canvas_with_from
        end
    end
  end

  defp push_horizontal(from_canvas, to_canvas, time, direction) do
    width = from_canvas.width
    # Fixed separation for now
    separation = 3

    # Calculate offset based on time
    total_distance = width + separation
    offset = round(time * total_distance)

    base_canvas = Canvas.new(width, from_canvas.height)

    case direction do
      :left ->
        # From canvas moves left (out the left side)
        canvas_with_from =
          if offset < width do
            from_part = Canvas.cut(from_canvas, {offset, 0}, {width - 1, from_canvas.height - 1})
            Canvas.overlay(base_canvas, from_part, offset: {0, 0})
          else
            base_canvas
          end

        # To canvas comes from right
        to_start_x = width + separation - offset

        if to_start_x < width and to_start_x >= 0 do
          to_width_visible = min(width - to_start_x, to_canvas.width)

          if to_width_visible > 0 do
            to_part = Canvas.cut(to_canvas, {0, 0}, {to_width_visible - 1, to_canvas.height - 1})
            Canvas.overlay(canvas_with_from, to_part, offset: {to_start_x, 0})
          else
            canvas_with_from
          end
        else
          canvas_with_from
        end

      :right ->
        # From canvas moves right (out the right side)
        canvas_with_from =
          if offset < width do
            from_width_visible = width - offset

            if from_width_visible > 0 do
              from_part =
                Canvas.cut(from_canvas, {0, 0}, {from_width_visible - 1, from_canvas.height - 1})

              Canvas.overlay(base_canvas, from_part, offset: {offset, 0})
            else
              base_canvas
            end
          else
            base_canvas
          end

        # To canvas comes from left
        to_end_x = offset - separation - 1

        if to_end_x >= 0 do
          to_width_visible = min(to_end_x + 1, to_canvas.width)

          if to_width_visible > 0 do
            to_source_start_x = max(0, to_canvas.width - to_width_visible)

            to_part =
              Canvas.cut(
                to_canvas,
                {to_source_start_x, 0},
                {to_canvas.width - 1, to_canvas.height - 1}
              )

            Canvas.overlay(canvas_with_from, to_part, offset: {0, 0})
          else
            canvas_with_from
          end
        else
          canvas_with_from
        end
    end
  end

  defp slide_horizontal(from_canvas, to_canvas, time, direction) do
    width = from_canvas.width
    offset = round(time * width)

    base_canvas = Canvas.new(width, from_canvas.height)

    case direction do
      :right ->
        # From canvas slides out to the right
        canvas_with_from =
          if offset < width do
            _from_width_visible = width - offset

            from_part =
              Canvas.cut(from_canvas, {0, 0}, {width - offset - 1, from_canvas.height - 1})

            Canvas.overlay(base_canvas, from_part, offset: {offset, 0})
          else
            base_canvas
          end

        # To canvas slides in from the left
        if offset > 0 do
          to_width_visible = min(offset, to_canvas.width)
          _to_source_start_x = max(0, to_canvas.width - to_width_visible)

          to_part =
            Canvas.cut(
              to_canvas,
              {to_canvas.width - to_width_visible, 0},
              {to_canvas.width - 1, to_canvas.height - 1}
            )

          Canvas.overlay(canvas_with_from, to_part, offset: {0, 0})
        else
          canvas_with_from
        end

      :left ->
        # From canvas slides out to the left
        canvas_with_from =
          if offset < width do
            _from_width_visible = width - offset
            from_part = Canvas.cut(from_canvas, {offset, 0}, {width - 1, from_canvas.height - 1})
            Canvas.overlay(base_canvas, from_part, offset: {0, 0})
          else
            base_canvas
          end

        # To canvas slides in from the right
        if offset > 0 do
          to_width_visible = min(offset, to_canvas.width)
          to_part = Canvas.cut(to_canvas, {0, 0}, {to_width_visible - 1, to_canvas.height - 1})
          Canvas.overlay(canvas_with_from, to_part, offset: {width - offset, 0})
        else
          canvas_with_from
        end
    end
  end

  defp slide_vertical(from_canvas, to_canvas, time, direction) do
    height = from_canvas.height
    offset = round(time * height)

    base_canvas = Canvas.new(from_canvas.width, height)

    case direction do
      :down ->
        # From canvas slides out downward
        canvas_with_from =
          if offset < height do
            _from_height_visible = height - offset

            from_part =
              Canvas.cut(from_canvas, {0, 0}, {from_canvas.width - 1, height - offset - 1})

            Canvas.overlay(base_canvas, from_part, offset: {0, offset})
          else
            base_canvas
          end

        # To canvas slides in from the top
        if offset > 0 do
          to_height_visible = min(offset, to_canvas.height)
          _to_source_start_y = max(0, to_canvas.height - to_height_visible)

          to_part =
            Canvas.cut(
              to_canvas,
              {0, to_canvas.height - to_height_visible},
              {to_canvas.width - 1, to_canvas.height - 1}
            )

          Canvas.overlay(canvas_with_from, to_part, offset: {0, 0})
        else
          canvas_with_from
        end

      :up ->
        # From canvas slides out upward
        canvas_with_from =
          if offset < height do
            _from_height_visible = height - offset
            from_part = Canvas.cut(from_canvas, {0, offset}, {from_canvas.width - 1, height - 1})
            Canvas.overlay(base_canvas, from_part, offset: {0, 0})
          else
            base_canvas
          end

        # To canvas slides in from the bottom
        if offset > 0 do
          to_height_visible = min(offset, to_canvas.height)
          to_part = Canvas.cut(to_canvas, {0, 0}, {to_canvas.width - 1, to_height_visible - 1})
          Canvas.overlay(canvas_with_from, to_part, offset: {0, height - offset})
        else
          canvas_with_from
        end
    end
  end
end
