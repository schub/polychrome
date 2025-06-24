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
  GameScheduler
}

IEx.configure(inspect: [limit: :infinity, printable_limit: :infinity])
Logger.configure(level: :info)

mario = Sprite.load("256-characters-original", 0)
