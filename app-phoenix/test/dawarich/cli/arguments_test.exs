defmodule Dawarich.CLI.ArgumentsTest do
  use Dawarich.JobsCase

  alias Dawarich.A12eCorpus

  defp refused(name, argv) do
    c = A12eCorpus.case!(name)
    untouched = A12eCorpus.replay(%{c | "argv" => []}).checks
    result = A12eCorpus.replay(%{c | "argv" => argv})
    assert {result.exit, result.stdout} == {1, ""}, inspect(argv)
    assert result.stderr =~ ~r/usage/i, inspect(argv)
    assert result.checks == untouched, inspect(argv)
  end

  test "clear-verified with a flag, a partial month or a malformed rake name clears nothing" do
    for argv <- [
          ~w(raw-data clear-verified --help),
          ~w(raw-data clear-verified 1 2026),
          ["points:raw_data:clear_verified[1,2026,1"],
          ["points:raw_data:clear_verified[1,", "2026,", "1]"],
          ["points:raw_data:clear_verified[1,2026]"]
        ],
        do: refused("raw_data_clear_all", argv)
  end

  test "users activate with an argument activates nobody" do
    refused("users_activate", ~w(users activate --help))
  end

  test "archive-full and reset-all with an argument archive, clear and delete nothing" do
    refused("raw_data_archive_full", ~w(raw-data archive-full --dry-run))
    refused("raw_data_reset_all", ~w(raw-data reset-all now))
  end
end
