defmodule Dawarich.A12f3bE061CloudGuardTest do
  use Dawarich.DataCase, async: false

  alias Dawarich.Release
  alias Dawarich.Release.Lifecycle

  @tag a12f3b_case: "E061-cloud-guard"
  test "E061 review Cloud Rails-off refuses native lifecycle with current ledgers and no writes" do
    assert Release.readiness(repo: Repo, env: %{}) == :ready
    before = snapshot()

    for legacy <- [nil, "false", "true", ""] do
      env =
        Map.reject(
          %{
            "DAWARICH_RAILS" => "off",
            "SELF_HOSTED" => "false",
            "DAWARICH_PHOENIX_LIFECYCLE" => legacy
          },
          fn {_key, value} -> is_nil(value) end
        )

      opts = [repo: Repo, env: env, command: fn _ -> flunk("Rails command invoked") end]

      assert Release.readiness(opts) == :schemas_behind
      assert Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}

      assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, fn ->
        Release.migrate(opts)
      end

      assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, fn ->
        Release.seed(opts)
      end

      assert snapshot() == before
    end
  end

  defp snapshot do
    Enum.map(
      ~w(public.schema_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations phoenix.registration_setting phoenix.release_migration_jobs public.job_outbox oban.oban_jobs),
      fn table ->
        Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY 1", [], log: false).rows
      end
    ) ++ [Repo.query!("SELECT nspname FROM pg_namespace ORDER BY nspname", [], log: false).rows]
  end
end
