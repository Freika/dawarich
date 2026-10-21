defmodule DawarichWeb.PageAcceptTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.PageAccept

  @corpus Jason.decode!(
            File.read!(Path.expand("../fixtures/page_envelopes/accept_corpus.json", __DIR__))
          )

  @tag envelope: :generated_accept
  test "generated Rails corpus preserves every ordered format refusal and calendar selection" do
    assert @corpus |> Enum.map(& &1["accept"]) |> Enum.uniq() |> length() >= 200

    mismatches =
      for probe <- @corpus,
          actual = PageAccept.formats(probe["accept"] || "", probe["xhr"]),
          expected = probe["formats"] || :invalid_type,
          actual != expected,
          do: {probe["accept"], probe["xhr"], expected, actual}

    assert mismatches == []

    for probe <- @corpus, Map.has_key?(probe, "formats") do
      formats = PageAccept.formats(probe["accept"] || "", probe["xhr"])
      actual = PageAccept.negotiate(formats, ~w(text/vnd.turbo-stream.html text/html))
      assert actual == probe["calendar"], probe["accept"] || "absent"
    end
  end
end
