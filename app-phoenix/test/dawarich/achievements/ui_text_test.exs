defmodule Dawarich.Achievements.UiTextTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.UiText

  @fixture Path.expand("../../fixtures/achievements_ui/text.json", __DIR__)
           |> File.read!()
           |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    :ok
  end

  for record <- @fixture["clocks"] do
    test "actual Rails local timestamp #{record["zone"]} #{record["utc"]}" do
      {:ok, instant, _} = DateTime.from_iso8601(unquote(record["utc"]))

      assert UiText.timestamp(%{"timezone" => unquote(record["zone"])}, instant) ==
               unquote(record["stamp"])
    end
  end

  for record <- @fixture["search"] do
    test "actual Rails transliteration #{record["text"]}" do
      assert UiText.search(unquote(record["text"])) == unquote(record["expected"])
    end
  end

  test "query uses hundred codepoints, preserving combining clusters and Ruby whitespace" do
    assert UiText.query(" " <> String.duplicate("é", 51) <> " ") == String.duplicate("é", 50)
    assert UiText.query(" Germany ") == " Germany "
  end

  test "query keeps the Unicode line and paragraph separators Ruby's strip leaves" do
    for separator <- [<<0x2028::utf8>>, <<0x2029::utf8>>, <<0x85::utf8>>] do
      assert UiText.query(separator <> "x" <> separator) == separator <> "x" <> separator
    end

    assert UiText.query(<<0x0B, ?x, 0x0B>>) == "x"
  end
end
