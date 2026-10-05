defmodule Dawarich.CLI.MigrateTest do
  use ExUnit.Case, async: false

  alias Dawarich.{CLI, Repo, ScratchRepo}
  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseMigrations.Unreleased
  alias Dawarich.ReleaseMigrator.Floor

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
  end

  defp status(prepare) do
    {:error, {:done, result}} =
      ScratchRepo.transaction(fn ->
        prepare.()
        {:ok, out} = StringIO.open("")
        {:ok, err} = StringIO.open("")

        code =
          CLI.run(["migrate", "status"], %{
            repo: ScratchRepo,
            out: out,
            err: err,
            stdin: out,
            env: %{}
          })

        ScratchRepo.rollback({:done, {code, out |> StringIO.contents() |> elem(1)}})
      end)

    result
  end

  defp forget(version),
    do: ScratchRepo.query!("DELETE FROM public.schema_migrations WHERE version = $1", [version])

  test "a current database reports a current public schema and exits 0" do
    assert {0, out} = status(fn -> :ok end)
    assert out =~ ~r/^phoenix and oban schemas: /m
    assert out =~ ~r/^public schema: current$/m
  end

  test "pending versions are listed under their release" do
    version = Unreleased |> ReleaseMigration.versions() |> List.last()
    assert {0, out} = status(fn -> forget(version) end)
    assert out =~ ~r/^public schema: 1 pending version$/m
    assert out =~ ~r/^  unreleased #{version}$/m
  end

  test "a database below the 1.0.0 floor is refused with the remedy and exits 1" do
    assert {1, out} = status(fn -> forget(hd(Floor.versions())) end)
    assert out =~ "public schema: refused: this database has not reached Dawarich"
    assert out =~ "start the Dawarich 1.15.2 image once"
  end

  test "migrate creates the phoenix and oban schemas" do
    Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")
    {:ok, out} = StringIO.open("")
    assert CLI.run(["migrate"], %{out: out, err: out, stdin: out, env: %{}}) == 0
    assert Repo.query!("SELECT to_regclass('phoenix.job_owners') IS NOT NULL").rows == [[true]]
    assert StringIO.contents(out) |> elem(1) == "phoenix and oban schemas: current\n"
  end

  test "native migrate reports refused upgrades and retains the floor remedy" do
    ScratchRepo.transaction(fn ->
      forget(hd(Floor.versions()))
      {:ok, out} = StringIO.open("")
      {:ok, err} = StringIO.open("")

      ctx = %{
        repo: ScratchRepo,
        out: out,
        err: err,
        stdin: out,
        env: %{"DAWARICH_PHOENIX_LIFECYCLE" => "true", "SELF_HOSTED" => "true"}
      }

      assert CLI.run(["migrate"], ctx) == 1
      assert StringIO.contents(err) |> elem(1) =~ "start the Dawarich 1.15.2 image once"
      assert StringIO.contents(out) |> elem(1) == ""
      ScratchRepo.rollback(:done)
    end)

    {:ok, out} = StringIO.open("")
    assert CLI.run(["db:migrate"], %{out: out, err: out, stdin: out, env: %{}}) == 1
    assert StringIO.contents(out) |> elem(1) =~ "native lifecycle is disabled"
  end
end
