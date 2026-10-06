defmodule Dawarich.ReadinessTest do
  use Dawarich.DataCase, async: false

  test "ready requires current native ledgers database and required Redis" do
    {:ok, redis} = Redix.start_link(Application.fetch_env!(:dawarich, :redis)[:url])
    on_exit(fn -> if Process.alive?(redis), do: GenServer.stop(redis) end)

    opts = [
      repo: Repo,
      env: %{"SELF_HOSTED" => "true", "DAWARICH_PHOENIX_LIFECYCLE" => "true"},
      redis: fn -> Dawarich.Redis.command(["PING"], redis) end
    ]

    Repo.query!("SET LOCAL timezone = 'UTC'", [], log: false)
    assert Dawarich.Readiness.check(opts) == :ready

    for table <-
          ~w(public.schema_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations) do
      %{rows: [[version]]} =
        Repo.query!(
          "DELETE FROM #{table} WHERE version = (SELECT max(version) FROM #{table}) RETURNING version",
          [],
          log: false
        )

      assert Dawarich.Readiness.check(opts) == {:unavailable, :lifecycle}
      Repo.query!("INSERT INTO #{table}(version) VALUES($1)", [version], log: false)
      assert Dawarich.Readiness.check(opts) == :ready
    end

    assert Dawarich.Readiness.check(
             release: fn _ -> :ready end,
             database: fn -> {:ok, %{rows: [[1]]}} end,
             redis: fn -> {:ok, "PONG"} end
           ) == :ready

    assert Dawarich.Readiness.check(
             release: fn _ -> :schemas_behind end,
             database: fn -> {:ok, %{rows: [[1]]}} end,
             redis: fn -> {:ok, "PONG"} end
           ) == {:unavailable, :lifecycle}
  end

end
