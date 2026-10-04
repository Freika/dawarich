defmodule Dawarich.CLITest do
  use ExUnit.Case, async: true

  alias Dawarich.CLI
  alias Dawarich.CLI.{RawData, Users}

  defmodule RaisingRepo do
    def query!(_sql, _params, _opts),
      do: raise(DBConnection.ConnectionError, "tcp connect (db:5432): connection refused")
  end

  defp io(extra \\ %{}) do
    {:ok, out} = StringIO.open("")
    {:ok, err} = StringIO.open("")
    Map.merge(%{out: out, err: err, stdin: out, env: %{}}, extra)
  end

  defp text(pid), do: pid |> StringIO.contents() |> elem(1)

  test "rake task names with bracket arguments resolve to the dawarich command" do
    assert CLI.resolve(["points:raw_data:restore[ 7 , 2026,1]"]) ==
             {:ok, {RawData, :restore}, ["7", "2026", "1"]}

    assert CLI.resolve(["points:raw_data:initial_archive"]) == {:ok, {RawData, :archive}, []}

    assert CLI.resolve(["users", "admin", "a@b.invalid"]) ==
             {:ok, {Users, :admin}, ["a@b.invalid"]}
  end

  test "a rake name resolves only in rake's own name[args] grammar and with nothing after it" do
    for argv <- [
          ["points:raw_data:clear_verified[1,2026,1"],
          ["points:raw_data:clear_verified[1,2026,1]x"],
          ["points:raw_data:clear_verified[1,", "2026,", "1]"],
          ["points:raw_data:clear_verified", "1"],
          ["users:activate", "--help"]
        ],
        do: assert(CLI.resolve(argv) == :unknown, inspect(argv))
  end

  test "retired rake tasks explain what replaced them and exit 1" do
    ctx = io()
    assert CLI.run(["dawarich:jobs:rehome[command:trips.calculate]"], ctx) == 1
    assert text(ctx.err) =~ "removed together with Sidekiq"
    assert text(ctx.out) == ""
  end

  test "an unknown command prints the usage on stderr and exits 1" do
    ctx = io()
    assert CLI.run(["users"], ctx) == 1
    assert text(ctx.err) =~ "Usage: dawarich COMMAND"
  end

  test "help lists every command and exits 0" do
    ctx = io()
    assert CLI.run(["help"], ctx) == 0
    help = text(ctx.out)

    for path <- CLI.commands(),
        do:
          assert(help =~ ~r/^  #{Regex.escape(Enum.join(path, " "))}( |$)/m, Enum.join(path, " "))
  end

  test "help lists standalone migrate with its own description" do
    ctx = io()
    assert CLI.run(["help"], ctx) == 0
    assert text(ctx.out) =~ ~r/^  migrate {2,}\S/m
  end

  test "an exception inside a command becomes one stderr line and exit 1" do
    ctx = io(%{repo: RaisingRepo, env: %{"SELF_HOSTED" => "true"}})
    assert CLI.run(["users", "activate"], ctx) == 1
    assert text(ctx.err) == "dawarich: tcp connect (db:5432): connection refused\n"
  end
end
