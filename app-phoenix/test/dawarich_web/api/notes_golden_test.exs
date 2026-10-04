defmodule DawarichWeb.Api.NotesGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_notes/golden.json" |> File.read!() |> Jason.decode!()
  @now @golden["now"] |> DateTime.from_iso8601() |> elem(1)
  @moduletag api_now: @now
  @moduletag :capture_log
  @tables ~w(users trips areas visits places notes action_text_rich_texts)

  for kase <- @golden["cases"] do
    @kase kase
    @tag golden_case: String.to_atom(kase["name"])
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      for {name, value} <- @kase["env"], do: System.put_env(name, value)

      for [table, rows] <- @golden["setups"][@kase["setup"]], row <- rows do
        assert table in @tables
        ApiGolden.insert!(table, row)
      end

      for {name, value} <- @golden["sequences"],
          do: Repo.query!("SELECT setval($1::text::regclass, $2, false)", [name, value])

      before = rows()
      ApiGolden.check(@kase, port, upstream)
      assert rows() == if(@kase["expect"] == "own", do: @kase["after"], else: before)
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
