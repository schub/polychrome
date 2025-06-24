defmodule Octopus.AppTest do
  use ExUnit.Case, async: false
  alias Octopus.{App, Mixer}

  setup do
    # Start the mixer if not already started
    case GenServer.whereis(Mixer) do
      nil -> start_supervised!(Mixer)
      _pid -> :ok
    end

    :ok
  end

  test "get_display_info returns valid display information" do
    display_info = App.get_display_info()

    assert is_integer(display_info.width)
    assert is_integer(display_info.height)
    assert is_integer(display_info.panel_width)
    assert is_integer(display_info.panel_height)
    assert is_integer(display_info.panel_count)
    assert is_integer(display_info.panel_gap)
    assert is_function(display_info.panel_range, 2)
    assert is_function(display_info.panel_at_coord, 2)
  end

  test "display info contains reasonable values" do
    display_info = App.get_display_info()

    # Basic sanity checks
    assert display_info.width > 0
    assert display_info.height > 0
    assert display_info.panel_width > 0
    assert display_info.panel_height > 0
    assert display_info.panel_count > 0
    assert display_info.panel_gap >= 0
  end

  test "panel functions work as expected" do
    display_info = App.get_display_info()

    # Test panel_range for first panel
    {start_x, end_x} = display_info.panel_range.(0, :x)
    {start_y, end_y} = display_info.panel_range.(0, :y)

    assert start_x >= 0
    assert end_x >= start_x
    assert start_y >= 0
    assert end_y >= start_y

    # Test panel_at_coord
    panel_id = display_info.panel_at_coord.(start_x, start_y)
    assert panel_id == 0
  end

  test "derived center values can be calculated" do
    display_info = App.get_display_info()

    # These are the values that PixelFun would calculate
    center_x = display_info.width / 2 - 0.5
    center_y = display_info.height / 2 - 0.5

    assert is_float(center_x)
    assert is_float(center_y)
    assert center_x >= 0
    assert center_y >= 0
  end
end
