defmodule Dawarich.NativeLifecycleTest do
  use Dawarich.DataCase, async: false

  alias Dawarich.Release
  alias Dawarich.Release.Lifecycle

  @tag :a12f4_a02_1
  test "standalone native lifecycle is mandatory in both deployment modes" do
    for hosted <- [nil, "true", "false"], legacy <- [nil, "", "false", "true"] do
      env = %{
        "DAWARICH_RAILS" => "off",
        "SELF_HOSTED" => hosted,
        "DAWARICH_PHOENIX_LIFECYCLE" => legacy
      }

      assert Lifecycle.mode(env) == {:ok, :native}
    end

    assert Lifecycle.mode(%{}) == {:ok, :rails}
    assert Lifecycle.mode(%{"SELF_HOSTED" => "false"}) == {:ok, :rails}
  end

  @tag :a12f4_a02_2
  test "standalone native readiness refuses a pending public version without writes" do
    for hosted <- [nil, "true", "false"] do
      opts = [repo: Repo, env: %{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => hosted}]
      assert Release.readiness(opts) == :ready

      %{rows: [[version]]} =
        Repo.query!(
          "DELETE FROM public.schema_migrations WHERE version = (SELECT max(version) FROM public.schema_migrations) RETURNING version",
          [],
          log: false
        )

      before = snapshot()
      assert Release.readiness(opts) == :schemas_behind
      assert snapshot() == before
      Repo.query!("INSERT INTO public.schema_migrations(version) VALUES($1)", [version], log: false)
      assert Release.readiness(opts) == :ready
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
