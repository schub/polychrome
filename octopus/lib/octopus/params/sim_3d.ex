defmodule Octopus.Params.Sim3d do
  use Octopus.Params, prefix: :sim_3d

  def topic, do: "sim_3d"

  def diameter, do: param(:diameter, 20.0)
  def strength, do: param(:strength, 5.0)

  def handle_param("diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:diameter, value})
  end

  def handle_param("strength", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:strength, value})
  end
end
