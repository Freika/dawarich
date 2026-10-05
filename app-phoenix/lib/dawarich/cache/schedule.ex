defmodule Dawarich.Cache.Schedule do
  @moduledoc false

  alias Dawarich.RailsCommands

  def preheat_user(repo, user_id, opts \\ []) do
    payload = %{
      "user_id" => user_id,
      "time_zone" => Keyword.get(opts, :time_zone, System.get_env("TIME_ZONE", "Europe/Berlin")),
      "source_job_id" => Keyword.get_lazy(opts, :source_job_id, &Ecto.UUID.generate/0),
      "run_at" =>
        Keyword.get_lazy(opts, :clock, fn -> System.os_time(:second) end) +
          Keyword.get(opts, :schedule_in, 0)
    }

    {:ok, :ok} =
      repo.transaction(fn -> RailsCommands.insert!(repo, "cache.preheat_user", payload) end)

    :ok
  end
end
