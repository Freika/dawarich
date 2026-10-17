defmodule Dawarich.MapWindowStatementsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.MapWindow

  @now ~U[2026-09-29 10:00:00Z]
  @berlin %{"timezone" => "Europe/Berlin"}

  for {params, expected} <- [
        {%{"start_at" => "2026-01-01", "end_at" => "2026-01-02"}, 2},
        {%{}, 3},
        {%{"date" => "2026-05-28"}, 3}
      ] do
    test "a warm window for #{inspect(params)} takes #{expected} statements" do
      MapWindow.build(unquote(Macro.escape(params)), @berlin, @now, nil, %{})

      assert statements(fn ->
               MapWindow.build(unquote(Macro.escape(params)), @berlin, @now, nil, %{})
             end) ==
               unquote(expected)
    end
  end

  defp statements(fun) do
    owner = self()
    key = {__MODULE__, make_ref()}

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, _, _ -> if self() == owner, do: send(owner, key) end,
      nil
    )

    try do
      fun.()
      count(key, 0)
    after
      :telemetry.detach(key)
    end
  end

  defp count(key, n) do
    receive do
      ^key -> count(key, n + 1)
    after
      0 -> n
    end
  end
end
