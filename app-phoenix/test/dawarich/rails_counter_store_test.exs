defmodule Dawarich.RailsCounterStoreTest do
  use Dawarich.JobsCase

  defp heredoc(path, pattern) do
    [_, body] = Regex.run(pattern, File.read!(Path.expand(path, __DIR__)))
    body |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp numbered(sql) do
    [head | rest] = String.split(sql, "?")

    rest
    |> Enum.with_index(1)
    |> Enum.reduce(head, fn {part, n}, acc -> acc <> "$#{n}" <> part end)
  end

  test "Rails' counter store runs Dawarich.State's increment, so both runtimes count one row" do
    rails =
      heredoc(
        "../../../lib/rack_attack/phoenix_counter_store.rb",
        ~r/INCREMENT = <<~SQL\.squish\n(.*?)\n\s*SQL\n/s
      )

    phoenix = heredoc("../../lib/dawarich/state.ex", ~r/@increment """\n(.*?)\n\s*"""/s)
    assert numbered(rails) == phoenix

    key = "rack::attack:1:t:x"
    assert Dawarich.State.increment(ScratchRepo, key, 1, 60) == 1
    assert ScratchRepo.query!(numbered(rails), [key, 1, 60], log: false).rows == [[2]]
    assert Dawarich.State.increment(ScratchRepo, key, -1, 1) == 1
    assert rows("SELECT value FROM phoenix.counters WHERE key = $1", [key]) == [[1]]
  end
end
