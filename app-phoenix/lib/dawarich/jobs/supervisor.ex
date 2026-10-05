defmodule Dawarich.Jobs.Supervisor do
  @moduledoc false
  use Supervisor, restart: :transient

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Dawarich.Mail.Delivery.warn_if_unkeyed(Dawarich.RailsSecret.fetch())

    workers = [
      Supervisor.child_spec({Dawarich.Jobs.Relay, opts}, shutdown: 1_000),
      {Dawarich.Jobs.Claimer, Keyword.take(opts, [:oban, :repo, :entries])}
    ]

    children = [
      {Dawarich.Jobs.Drain, Keyword.take(opts, [:oban])},
      %{
        id: :workers,
        type: :supervisor,
        restart: :transient,
        start:
          {Supervisor, :start_link,
           [workers, [strategy: :one_for_one, max_restarts: 1_000, max_seconds: 60]]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
