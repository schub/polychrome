defmodule Octopus.AppSupervisorTest do
  use ExUnit.Case, async: false
  alias Octopus.{AppSupervisor, App}

  test "get_installation_info returns expected data" do
    info = App.get_installation_info()

    assert is_integer(info.panel_count)
    assert is_integer(info.panel_width)
    assert is_integer(info.panel_height)
    assert is_integer(info.panel_gap)
    assert is_integer(info.width)
    assert is_integer(info.height)

    # Verify calculated width matches expected value
    expected_width = info.panel_count * info.panel_width
    assert info.width >= expected_width
  end

  test "start_app works with compatible apps" do
    # Test with an app that should be compatible (Canvas Test)
    assert {:ok, app_id} = AppSupervisor.start_app(Octopus.Apps.CanvasTest)
    assert is_binary(app_id)

    # Verify it's in running apps
    running = AppSupervisor.running_apps()
    assert Enum.any?(running, fn {module, ^app_id} -> module == Octopus.Apps.CanvasTest end)

    # Clean up
    AppSupervisor.stop_app(app_id)
  end

  test "all real apps implement compatible? callback" do
    available = AppSupervisor.available_apps()

    for app_module <- available do
      # Should not raise - all apps should have compatible?/0
      result = apply(app_module, :compatible?, [])
      assert is_boolean(result)
    end
  end
end
