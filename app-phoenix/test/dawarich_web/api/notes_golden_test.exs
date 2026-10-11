defmodule DawarichWeb.Api.NotesGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_notes/golden.json" |> File.read!() |> Jason.decode!()
  @now @golden["now"] |> DateTime.from_iso8601() |> elem(1)
  @moduletag api_now: @now
  @moduletag :capture_log
  @tables ~w(users trips areas visits places notes action_text_rich_texts)

  setup_all do
    {:ok, golden: File.read!("test/fixtures/api_notes/golden.json") |> Jason.decode!()}
  end

  for kase <- @golden["cases"] do
    @tag golden_case: String.to_atom(kase["name"])
    @case_name kase["name"]
    test "golden #{kase["name"]}", %{port: port, upstream: upstream, golden: golden} do
      kase = Enum.find(golden["cases"], &(&1["name"] == @case_name))
      for {name, value} <- kase["env"], do: System.put_env(name, value)

      for [table, rows] <- golden["setups"][kase["setup"]], row <- rows do
        assert table in @tables
        ApiGolden.insert!(table, row)
      end

      for {name, value} <- @golden["sequences"],
          do: Repo.query!("SELECT setval($1::text::regclass, $2, false)", [name, value])

      ApiGolden.check(kase, port, upstream)
      assert rows() == Map.fetch!(kase, "after")
    end
  end

  defp rows do
    Repo.query!("SELECT set_config('TimeZone','UTC',true)")

    Map.new(~w(notes action_text_rich_texts), fn table ->
      rows = Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id").rows
      {table, Enum.map(rows, fn [text] -> Jason.decode!(text) end)}
    end)
  end
end
