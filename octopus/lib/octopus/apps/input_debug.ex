defmodule Octopus.Apps.InputDebug do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.Frame
  alias Octopus.ControllerEvent
  alias Octopus.{ButtonState, JoyState}

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule Screen do
    defstruct [:pixels]

    def new() do
      %Screen{
        pixels:
          [
            0
          ]
          |> Stream.cycle()
          |> Stream.take(8 * 8)
          |> Enum.to_list()
      }
    end

    defp index_to_coord(i) do
      {rem(i, 8), floor(i / 8)}
    end

    def set_pixels(%Screen{} = screen, tuples) do
      screen_map =
        screen.pixels
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {v, i}, acc ->
          acc
          |> Map.put(index_to_coord(i), v)
        end)

      screen_map =
        tuples
        |> Enum.reduce(screen_map, fn {coord, value}, acc ->
          acc |> Map.put(coord, value)
        end)

      new_pixels =
        0..63
        |> Enum.reduce([], fn i, acc ->
          [
            screen_map
            |> Map.get(index_to_coord(i))
            | acc
          ]
        end)
        |> Enum.reverse()

      %Screen{screen | pixels: new_pixels}
    end
  end

  defmodule State do
    defstruct [:position, :color, :palette, :screen, :button_state]
  end

  def name(), do: "Input Debugger"

  def app_init(_args) do
    state = %State{
      position: 0,
      color: 1,
      palette: ColorPalette.load("pico-8"),
      screen: Screen.new(),
      button_state: ButtonState.new()
    }

    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    render_frame(state)
    {:noreply, state}
  end

  def handle_input(
        %ControllerEvent{} = event,
        %State{button_state: bs} = state
      ) do
    Logger.info("Input Debug: #{inspect(event)}")

    new_bs = bs |> ButtonState.handle_event(event) |> IO.inspect()

    {:noreply, %State{state | button_state: new_bs}}
  end

  defp screen_button_color(6), do: 3
  defp screen_button_color(10), do: 6
  defp screen_button_color(9), do: 2
  defp screen_button_color(sb_index), do: 7 + sb_index

  defp get_button_positions() do
    num_buttons = Octopus.installation().num_buttons()

    # Define positions for up to 12 buttons - consecutive from top-left
    positions = [
      {1, {0, 0}},
      {2, {1, 0}},
      {3, {2, 0}},
      {4, {3, 0}},
      {5, {4, 0}},
      {6, {5, 0}},
      {7, {6, 0}},
      {8, {7, 0}},
      {9, {0, 1}},
      {10, {1, 1}},
      {11, {2, 1}},
      {12, {3, 1}}
    ]

    # Return only the positions for the number of buttons we have
    Enum.take(positions, num_buttons)
  end

  defp render_frame(%State{button_state: bs} = state) do
    num_buttons = Octopus.installation().num_buttons()

    # collect some painting
    pixel_tuples =
      get_button_positions()
      |> Enum.with_index()
      |> Enum.reduce([], fn {{b, coord}, index}, acc ->
        [
          {coord,
           if bs |> ButtonState.button?(b) do
             screen_button_color(index)
           else
             1
           end}
          | acc
        ]
      end)

    # Paint some joysticks (moved down one row to make room for buttons)
    screen =
      [{bs.joy1, {0, 4}}, {bs.joy2, {5, 4}}]
      |> Enum.map(fn {joy, {x, y}} ->
        [
          {:a, {0, 0}},
          {:u, {1, 1}},
          {:d, {1, 3}},
          {:l, {0, 2}},
          {:r, {2, 2}},
          {:middle, {1, 2}}
        ]
        |> Enum.map(fn {button, {offset_x, offset_y}} ->
          {{x + offset_x, y + offset_y},
           if JoyState.button?(joy, button) do
             case button do
               :a -> 8
               _ -> 7
             end
           else
             cond do
               button in [:a] -> 2
               true -> 5
             end
           end}
        end)
      end)
      |> Enum.reduce(state.screen, fn tuplelist, acc ->
        acc |> Screen.set_pixels(tuplelist)
      end)

    # Paint some pixels
    screen =
      screen
      |> Screen.set_pixels(pixel_tuples)

    paint_screen = fn data, screen_index ->
      data
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        if floor(i / 64) == screen_index do
          screen_button_color(screen_index)
        else
          v
        end
      end)
      |> Enum.to_list()
    end

    # Put screen on all windows
    data =
      screen.pixels
      |> Stream.cycle()
      |> Stream.take(8 * 8 * num_buttons)
      |> Enum.to_list()

    # make whole window light up for screen buttons
    data =
      0..(num_buttons - 1)
      |> Enum.reduce(data, fn i, acc ->
        cond do
          state.button_state |> ButtonState.screen_button?(i) ->
            paint_screen.(acc, i)

          true ->
            acc
        end
      end)

    %Frame{
      data: data,
      palette: state.palette
    }
    |> send_frame()
  end
end
