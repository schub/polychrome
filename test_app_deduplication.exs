#!/usr/bin/env elixir

# Test script for app deduplication functionality
Mix.install([])

# Start the Octopus application manually
Code.eval_file("config/config.exs")
Application.ensure_all_started(:octopus)

alias Octopus.AppSupervisor
alias Octopus.AppManager

IO.puts("Testing app deduplication functionality...")

# Check initial state
initial_apps = AppSupervisor.running_apps()
IO.puts("Initial running apps: #{inspect(initial_apps)}")

# Start a test app
test_module = Octopus.Apps.CanvasTest
IO.puts("Starting #{test_module} for the first time...")
{:ok, app_id1} = AppSupervisor.start_or_select_app(test_module)
IO.puts("Got app_id: #{app_id1}")

# Check running apps
apps_after_first = AppSupervisor.running_apps()
IO.puts("Running apps after first start: #{inspect(apps_after_first)}")

# Try to start the same app again
IO.puts("Starting #{test_module} again (should return existing app_id)...")
{:ok, app_id2} = AppSupervisor.start_or_select_app(test_module)
IO.puts("Got app_id: #{app_id2}")

# Check if they're the same
if app_id1 == app_id2 do
  IO.puts("✅ SUCCESS: App deduplication works! Same app_id returned.")
else
  IO.puts("❌ FAILURE: Different app_ids returned: #{app_id1} vs #{app_id2}")
end

# Check running apps again
apps_after_second = AppSupervisor.running_apps()
IO.puts("Running apps after second start: #{inspect(apps_after_second)}")

# Clean up
AppSupervisor.stop_app(app_id1)
IO.puts("Cleaned up test app")
