alias Octopus.{
  Protobuf,
  AppSupervisor,
  AppRegistry,
  Mixer,
  Apps,
  Font,
  Broadcaster,
  Transitions,
  Canvas,
  Sprite,
  GameScheduler,
  Installation
}

IEx.configure(inspect: [limit: :infinity, printable_limit: :infinity])
Logger.configure(level: :info)

mario =
  if Code.ensure_loaded?(Octopus) do
    Sprite.load("256-characters-original", 0)
  else
    nil
  end
