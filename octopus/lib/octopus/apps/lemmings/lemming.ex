alias Octopus.{Sprite, Canvas}

defmodule Lemming do
  # How many pixels of the lemming should remain visible when turning at boundaries
  @visible_pixels_when_turning 2
  # Standard lemming sprite width
  @lemming_width 8

  defstruct frames: nil,
            anchor: {-4, 0},
            anim_step: 0,
            state: :walk_right,
            offsets: %{},
            self_destruct: 999_999_999

  def play_sample(%Lemming{} = lem, name, display_info) do
    # Convert to 1-based for audio
    channel = current_panel(lem, display_info) + 1
    Octopus.App.play_sample("lemmings/#{name}.wav", channel)
    lem
  end

  def current_panel(%Lemming{anchor: {x, y}}, display_info) do
    panel_id = display_info.panel_at_coord.(x, y || 0)
    if panel_id == :not_found, do: 0, else: panel_id
  end

  def turn(%Lemming{anchor: {x, y}} = lem) do
    {new_state, xoffset} =
      cond do
        lem.state == :walk_right -> {:walk_left, -2}
        true -> {:walk_right, 2}
      end

    %Lemming{
      lem
      | state: new_state,
        anchor: {x + xoffset, y},
        frames: lem.frames |> Enum.map(&Canvas.flip(&1, :horizontal)),
        offsets: lem.offsets |> Enum.map(fn {i, {x, y}} -> {i, {-x, y}} end) |> Enum.into(%{})
    }
  end

  def explode(%Lemming{} = lem, display_info) do
    %Lemming{
      lem
      | state: :ohno,
        frames: Sprite.load(Path.join(["lemmings", "LemmingOhNo"])),
        anim_step: 0,
        offsets: %{}
    }
    |> Lemming.play_sample("ohno", display_info)
  end

  def explode_really(%Lemming{} = lem, display_info) do
    %Lemming{
      lem
      | state: :explode,
        frames: Sprite.load(Path.join(["lemmings", "LemmingExplode"])),
        anim_step: 0,
        offsets: %{}
    }
    |> Lemming.play_sample("thud", display_info)
  end

  def splat(%Lemming{} = lem, display_info) do
    %Lemming{
      anchor: lem.anchor,
      state: :splat,
      frames: Sprite.load(Path.join(["lemmings", "LemmingSplat"])),
      anim_step: 0
    }
    |> Lemming.play_sample("splat", display_info)
  end

  def walking_right(display_info) do
    panel_width = display_info.panel_width
    panel_gap = display_info.panel_gap
    panel_stride = panel_width + panel_gap

    %Lemming{
      anchor: {-panel_stride / 2, 0},
      frames: Sprite.load(Path.join(["lemmings", "LemmingWalk"])),
      offsets: 0..7 |> Enum.map(fn i -> {i, {1, 0}} end) |> Enum.into(%{})
    }
  end

  def walking_left(display_info) do
    panel_width = display_info.panel_width
    panel_gap = display_info.panel_gap
    panel_stride = panel_width + panel_gap

    %Lemming{
      (walking_right(display_info)
       |> turn())
      | anchor: {display_info.width - 2 * panel_stride, 0}
    }
  end

  def stopper(display_info, pos) do
    {start_x, _end_x} = display_info.panel_range.(pos, :x)

    %Lemming{
      anchor: {start_x, 0},
      frames: Sprite.load(Path.join(["lemmings", "LemmingStopper"])),
      state: :stopper
    }
  end

  def faller(display_info, pos) do
    {start_x, _end_x} = display_info.panel_range.(pos, :x)

    new_lem = %Lemming{
      state: :fall,
      anchor: {start_x, -8},
      frames: Sprite.load(Path.join(["lemmings", "LemmingFall"]))
    }

    new_lem =
      if :rand.uniform(2) == 1 do
        %Lemming{new_lem | frames: new_lem.frames |> Enum.map(&Canvas.flip(&1, :horizontal))}
      else
        new_lem
      end

    %Lemming{
      new_lem
      | offsets:
          0..(length(new_lem.frames) - 1) |> Enum.map(fn i -> {i, {0, 1}} end) |> Enum.into(%{})
    }
  end

  def button_lemming(display_info, number) do
    faller(display_info, number)
  end

  def tick(%Lemming{state: :ohno, anim_step: 7} = sprite, display_info) do
    Lemming.explode_really(sprite, display_info)
  end

  def tick(%Lemming{state: :fall, anchor: {_, 0}} = sprite, display_info) do
    case :rand.uniform(5) do
      5 ->
        Lemming.splat(sprite, display_info)

      4 ->
        %Lemming{
          Lemming.walking_right(display_info)
          | anchor: sprite.anchor
        }

      3 ->
        %Lemming{
          Lemming.walking_left(display_info)
          | anchor: sprite.anchor
        }

      2 ->
        sprite |> Lemming.play_sample("thunk", display_info)
        Lemming.stopper(display_info, Lemming.current_panel(sprite, display_info))

      1 ->
        inner_tick(sprite) |> Lemming.play_sample("ohno", display_info)
    end
  end

  def tick(%Lemming{} = sprite, _display_info) do
    inner_tick(sprite)
  end

  defp inner_tick(%Lemming{anchor: {0, 20}}), do: nil

  defp inner_tick(%Lemming{} = sprite) do
    {dx, dy} = Map.get(sprite.offsets, sprite.anim_step, {0, 0})
    {x, y} = sprite.anchor

    ticked = %Lemming{
      sprite
      | anchor: {x + dx, y + dy},
        anim_step: rem(sprite.anim_step + 1, length(sprite.frames))
    }

    if ticked.anim_step == 0 && ticked.state in [:splat, :explode] do
      nil
    else
      ticked
    end
  end

  def boundaries(%Lemming{state: :walk_right, anchor: {x, _}} = lem, _, [bound | tail]) do
    # Right-walker: compare walker's right edge to blocker's left edge
    display_info = Octopus.App.get_display_info()

    # Calculate gap distance, ensuring it's never negative
    hidden_pixels = @lemming_width - @visible_pixels_when_turning
    gap_distance = max(0, display_info.panel_gap - hidden_pixels)

    walker_right_edge = x + @lemming_width - 1
    blocker_left_edge = bound

    cond do
      walker_right_edge == blocker_left_edge - gap_distance -> turn(lem)
      true -> boundaries(lem, [], tail)
    end
  end

  def boundaries(%Lemming{state: :walk_left, anchor: {x, _}} = lem, [bound | tail], _) do
    # Left-walker: compare walker's left edge to blocker's right edge
    display_info = Octopus.App.get_display_info()

    # Calculate gap distance, ensuring it's never negative
    hidden_pixels = @lemming_width - @visible_pixels_when_turning
    gap_distance = max(0, display_info.panel_gap - hidden_pixels)

    walker_left_edge = x
    blocker_right_edge = bound

    cond do
      walker_left_edge == blocker_right_edge + gap_distance -> turn(lem)
      true -> boundaries(lem, tail, [])
    end
  end

  def boundaries(%Lemming{} = lem, _, _), do: lem

  def sprite(%Lemming{} = lem) do
    lem.frames
    |> Enum.at(lem.anim_step)
  end
end
