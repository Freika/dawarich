defmodule Dawarich.CLI.SeedsTest do
  use Dawarich.JobsCase
  alias Dawarich.{CLI, A12hSeeds}

  test "seeds and db:seed use native seeds only with lifecycle enabled" do
    c = A12hSeeds.case!("A12h_fresh")
    A12hSeeds.load!(ScratchRepo, c["after"], ~w(tags users countries regions))
    {:ok, out} = StringIO.open("")
    ctx = %{repo: ScratchRepo, out: out, err: out, stdin: out, env: %{}}
    before = snapshot()

    for command <- ["seeds", "db:seed"] do
      assert CLI.run([command], ctx) == 1
      assert StringIO.contents(out) |> elem(1) =~ "native lifecycle is disabled"
      assert snapshot() == before

      native = %{
        ctx
        | env: %{
            "DAWARICH_PHOENIX_LIFECYCLE" => "true",
            "SELF_HOSTED" => "true",
            "DATABASE_ADVISORY_LOCKS" => "false"
          }
      }

      assert CLI.run([command], native) == 0
      assert StringIO.contents(out) |> elem(1) =~ "ordinary seeds: current"
      assert snapshot() == before
    end
  end

  defp snapshot,
    do: Enum.map(~w(users countries regions tags), &A12hSeeds.snapshot(ScratchRepo, &1))
end
