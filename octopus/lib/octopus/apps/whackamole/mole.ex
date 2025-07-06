defmodule Octopus.Apps.Whackamole.Mole do
  defstruct [:panel, :start_tick]

  def new(panel, start_tick) do
    %__MODULE__{
      panel: panel,
      start_tick: start_tick
    }
  end
end
