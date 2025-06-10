defmodule Octopus.Repo do
  @adapter (case Mix.env() do
    :prod -> Ecto.Adapters.SQLite3
    _ -> Ecto.Adapters.Postgres
  end)

  use Ecto.Repo,
    otp_app: :octopus,
    adapter: @adapter
end
