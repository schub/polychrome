defmodule Octopus.Apps.Lemmings do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Events.Event.Controller, as: ControllerEvent
  alias Lemming

  @default_block_time 10

  defmodule State do
    defstruct t: 0, lemmings: [], actions: %{}, matrix: nil, button_map: %{}
  end

  def name(), do: "Lemmings"

  def icon(), do: Sprite.load("lemmings/LemmingWalk", 3)

  def app_init(_args) do
    installation = Application.get_env(:octopus, :installation)
    matrix = Octopus.VirtualMatrix.new(installation)
    panel_count = Octopus.VirtualMatrix.panel_count(matrix)

    button_map =
      1..panel_count
      |> Enum.map(fn i -> {"BUTTON_#{i}" |> String.to_atom(), i - 1} end)
      |> Enum.into(%{})

    state = %State{
      lemmings: [
        Lemming.walking_left(matrix),
        Lemming.walking_right(matrix),
        Lemming.stopper(matrix, :rand.uniform(panel_count - 2) + 1)
      ],
      matrix: matrix,
      button_map: button_map
    }

    :timer.send_interval(100, :tick)
    {:ok, state}
  end

  defp tick(state) do
    state
    |> tick_reaction()
    |> tick_postprocess()
  end

  defp tick_reaction(%State{t: t, matrix: matrix} = state) when t in [1600, 3200] do
    %State{
      state
      | lemmings: [
          Lemming.walking_left(matrix),
          Lemming.walking_right(matrix) | state.lemmings
        ]
    }
  end

  defp tick_reaction(%State{t: t, lemmings: lems, matrix: matrix} = state)
       when rem(t, 80) == 70 and length(lems) < 6 do
    {:noreply, new_state} =
      handle_number_button_press(
        state,
        :rand.uniform(Octopus.VirtualMatrix.panel_count(matrix)) - 1
      )

    new_state
  end

  defp tick_reaction(%State{t: t, lemmings: lems, matrix: matrix} = state)
       when rem(t, 80) == 70 and length(lems) > 8 do
    %State{state | lemmings: explode_first(state.lemmings, matrix)}
  end

  defp tick_reaction(state), do: state

  defp tick_postprocess(%State{matrix: matrix} = state) do
    # Render and send the current frame
    render_frame(state.lemmings, matrix)

    # Calculate boundaries from stopper lemmings
    boundaries = calculate_boundaries(state.lemmings, matrix)

    # Update all lemmings and advance time
    %State{
      state
      | lemmings: update_lemmings(state.lemmings, matrix, boundaries),
        t: state.t + 1
    }
  end

  defp render_frame(lemmings, matrix) do
    lemmings
    |> Enum.reduce(Canvas.new(matrix.width, matrix.height), fn sprite, canvas ->
      Canvas.overlay(canvas, Lemming.sprite(sprite), offset: sprite.anchor)
    end)
    |> (&Octopus.VirtualMatrix.send_frame(matrix, &1)).()
  end

  defp calculate_boundaries(lemmings, matrix) do
    lemmings
    |> Enum.reduce({[0], [matrix.width]}, fn
      %Lemming{state: :stopper} = lem, {left_bounds, right_bounds} ->
        window = Lemming.current_window(lem, matrix)
        {start_x, end_x} = Octopus.VirtualMatrix.panel_range(matrix, window - 1, :x)
        {[end_x + 1 | left_bounds], [start_x - 1 | right_bounds]}

      _, boundaries ->
        boundaries
    end)
  end

  defp update_lemmings(lemmings, matrix, boundaries) do
    {left_bounds, right_bounds} = boundaries

    lemmings
    |> Enum.map(&Lemming.tick(&1, matrix))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Lemming.boundaries(&1, left_bounds, right_bounds))
  end

  def action_allowed?(action_map, action, now, min_distance) do
    #    IO.inspect([action_map, action, now, min_distance])

    case Map.get(action_map, action) do
      nil -> true
      t when t <= now - min_distance -> true
      _ -> false
    end
  end

  def update_action(action_map, action, now, min_distance) do
    if (case Map.get(action_map, action) do
          nil -> true
          t when t <= now - min_distance -> true
          _ -> false
        end) do
      action_map |> Map.put(action, now)
    else
      action_map
    end
  end

  defp add_lemming(state, direction_fun) do
    action = __ENV__.function |> elem(0)
    new_lem = direction_fun.(state.matrix)

    if action_allowed?(state.actions, action, state.t, @default_block_time) do
      new_lem |> Lemming.play_sample("letsgo", state.matrix)
    end

    %State{
      state
      | lemmings:
          if action_allowed?(state.actions, action, state.t, 5) do
            [new_lem | state.lemmings]
          else
            state.lemmings
          end,
        actions: state.actions |> update_action(action, state.t, 5)
    }
  end

  def add_left(%State{} = state), do: add_lemming(state, &Lemming.walking_right/1)
  def add_left(state), do: state

  def add_right(%State{} = state), do: add_lemming(state, &Lemming.walking_left/1)
  def add_right(state), do: state

  def explode_first([%Lemming{state: state} = lem | tail], acc, matrix)
      when state in [:stopper, :walk_left, :walk_right] do
    ([Lemming.explode(lem, matrix) | tail] ++ acc) |> Enum.reverse()
  end

  def explode_first([lem | tail], acc, matrix), do: explode_first(tail, [lem | acc], matrix)
  def explode_first([], acc, _matrix), do: acc
  def explode_first(lems, matrix), do: explode_first(lems, [], matrix)

  def handle_info(:tick, %State{} = state) do
    {:noreply, tick(state)}
  end

  def handle_input(%ControllerEvent{type: :button, action: :press, button: button}, state) do
    # Convert to 0-based indexing for button_map
    button_index = button - 1
    handle_number_button_press(state, button_index)
  end

  def handle_input(
        %ControllerEvent{type: :joystick, joystick: _joystick, direction: :right},
        state
      ) do
    # Right direction adds left-walking lemming
    state = add_left(state)
    {:noreply, state}
  end

  def handle_input(
        %ControllerEvent{type: :joystick, joystick: _joystick, direction: :left},
        state
      ) do
    # Left direction adds right-walking lemming
    state = add_right(state)
    {:noreply, state}
  end

  def handle_input(
        %ControllerEvent{type: :joystick, joystick: _joystick, direction: :down},
        state
      ) do
    # Down direction explodes a lemming
    handle_kill(state)
  end

  def handle_input(_, state) do
    {:noreply, state}
  end

  def handle_kill(%State{lemmings: lems, matrix: matrix} = state) do
    action = :explode_random
    block_time = 5

    if action_allowed?(state.actions, action, state.t, block_time) do
      {:noreply,
       %State{
         state
         | lemmings: explode_first(lems, matrix),
           actions: state.actions |> update_action(action, state.t, block_time)
       }}
    else
      {:noreply, state}
    end
  end

  def handle_number_button_press(%State{matrix: matrix} = state, number) do
    action = "Button_#{number + 1}" |> String.to_atom()
    block_time = 12

    {lems, existing_stopper} =
      Enum.reduce(state.lemmings, {[], nil}, fn
        %Lemming{state: :stopper} = lem, {list, nil} ->
          if Lemming.current_window(lem, matrix) == number + 1 do
            {list, lem}
          else
            {[lem | list], nil}
          end

        lem, {list, es} ->
          {[lem | list], es}
      end)

    if action_allowed?(state.actions, action, state.t, block_time) do
      new_lems =
        if existing_stopper do
          [existing_stopper |> Lemming.explode(matrix) | lems]
        else
          new_lem =
            Lemming.button_lemming(matrix, number) |> Lemming.play_sample("yippee", matrix)

          [new_lem | state.lemmings]
        end

      {:noreply,
       %State{
         state
         | lemmings: new_lems,
           actions: state.actions |> update_action(action, state.t, block_time)
       }}
    else
      {:noreply, state}
    end
  end
end
