defmodule Dawarich.PublicBaselineTest do
  use ExUnit.Case, async: false

  alias Dawarich.{PublicBaseline, ReleaseMigrator, Repo}

  @columns ~w(map_matched_at map_matching_data map_matching_input_digest map_matching_status matched_path)

  test "reused main and scratch databases refresh an older public baseline and retain private schemas" do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)

    for repo <- [Repo, Dawarich.ScratchRepo, Dawarich.ScratchCaseRepo, Dawarich.TracksScratchRepo] do
      PublicBaseline.ensure_current!(repo)
      repo.query!("CREATE TABLE phoenix.baseline_probe (id integer)", [], log: false)

      try do
        original = repo.query!("SELECT 'public.tracks'::regclass::oid", [], log: false).rows
        PublicBaseline.ensure_current!(repo)

        assert repo.query!("SELECT 'public.tracks'::regclass::oid", [], log: false).rows ==
                 original

        repo.query!(
          "DELETE FROM public.schema_migrations WHERE version IN ('20261006120000', '20261006120100')",
          [],
          log: false
        )

        for column <- @columns,
            do: repo.query!("ALTER TABLE public.tracks DROP COLUMN #{column}", [], log: false)

        assert repo.query!("SELECT to_regclass('public.job_outbox') IS NOT NULL", [], log: false).rows ==
                 [[true]]

        PublicBaseline.ensure_current!(repo)

        assert repo.query!("SELECT to_regclass('phoenix.baseline_probe') IS NOT NULL", [],
                 log: false
               ).rows ==
                 [[true]]

        assert repo.query!("SELECT 'public.tracks'::regclass::oid", [], log: false).rows !=
                 original

        expected =
          Regex.scan(~r/\((\d{14})\)/, ReleaseMigrator.baseline_sql())
          |> Enum.map(fn [_, version] -> [version] end)
          |> Enum.sort()

        assert repo.query!("SELECT version FROM public.schema_migrations ORDER BY version", [],
                 log: false
               ).rows ==
                 expected

        assert repo.query!(
                 "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' " <>
                   "AND table_name = 'tracks' AND column_name = ANY($1) ORDER BY column_name",
                 [@columns],
                 log: false
               ).rows == Enum.map(Enum.sort(@columns), &[&1])
      after
        repo.query!("DROP TABLE phoenix.baseline_probe", [], log: false)
      end
    end
  end
end
