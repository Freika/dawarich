defmodule DawarichWeb.AchievementUnlockRevealTest do
  use ExUnit.Case, async: false
  alias Dawarich.Achievements.UiText
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.AchievementUnlockReveal

  test "renders Rails reveal markup actions and one versus multiple card stack" do
    corpus = "test/fixtures/achievement_unlocks/cards.json" |> File.read!() |> Jason.decode!()

    for locale <- ~w(en de es fr pl ca zh) do
      row = Enum.find(corpus["cards"], &(&1["name"] == locale <> "_flat_country"))

      for count <- [1, 2, 11] do
        html = AchievementUnlockReveal.render(row["card"], count, locale)
        doc = LazyHTML.from_fragment(html)
        assert LazyHTML.query(doc, "[data-testid='achievement-unlock-deck']") |> Enum.count() == 1

        assert LazyHTML.query(doc, "[data-action='click->achievement-unlocks#dismiss']")
               |> Enum.count() == 1

        assert LazyHTML.query(doc, "[data-action='click->achievement-unlocks#nextCard']")
               |> Enum.count() == 1

        assert LazyHTML.query(doc, ".ach-unlock-back") |> Enum.count() ==
                 if(count > 1, do: 2, else: 0)

        assert LazyHTML.query(doc, ".ach-unlock-next") |> LazyHTML.text() |> String.trim() ==
                 UiText.t(locale, "unlocks." <> if(count > 1, do: "next", else: "done"))

        assert LazyHTML.query(doc, ".ach-unlock-count") |> LazyHTML.text() ==
                 UiText.t(locale, "unlocks.remaining", %{"count" => count})

        assert LazyHTML.query(doc, ".ach-unlock-front") |> LazyHTML.attribute("href") == [
                 row["card"]["path"]
               ]

        assert html =~ "ach-spectral-wrap--sm"
        refute html =~ "phx-"
        refute html =~ "data-token"

        if locale in ~w(en de) and count == 2 do
          expected = File.read!("test/fixtures/achievement_unlocks/#{locale}_next.html")

          assert ParityHTML.normalize(html) == ParityHTML.normalize(expected),
                 ParityHTML.first_difference(
                   ParityHTML.normalize(html),
                   ParityHTML.normalize(expected)
                 )

          assert actions(html) == actions(expected)
          assert asset_paths(html) == asset_paths(expected)
        end
      end
    end

    card = Enum.find(corpus["cards"], &(&1["name"] == "en_subdivision"))["card"]

    card =
      card
      |> Map.put("name", "<script>alert('synthetic')</script>")
      |> Map.put("path", "/achievements/country_de?q=\"<img>")
      |> Map.update!("attributes", &Map.put(&1, "name", "<img onerror='synthetic'>"))

    html = AchievementUnlockReveal.render(card, 1, "en")
    refute html =~ "<script>"
    refute html =~ "<img"
    assert html =~ "&lt;img"

    assert LazyHTML.from_fragment(html)
           |> LazyHTML.query(".ach-unlock-front")
           |> LazyHTML.attribute("href") == [card["path"]]
  end

  defp actions(html),
    do:
      ParityHTML.stimulus(html, "[data-action], [data-testid]")
      |> Enum.map(fn {tag, attrs} ->
        {tag,
         Enum.reject(attrs, fn {key, _} ->
           key in ["data-achievement-card-paper-value", "data-achievement-card-foil-value"]
         end)}
      end)

  defp asset_paths(html) do
    for key <- ~w(data-achievement-card-paper-value data-achievement-card-foil-value) do
      [path] =
        LazyHTML.from_fragment(html) |> LazyHTML.query("[#{key}]") |> LazyHTML.attribute(key)

      String.replace(path, ~r/-[0-9a-f]{8,}(?=\.webp$)/, "")
    end
  end
end
