defmodule DawarichWeb.TimeAgoTest do
  use ExUnit.Case, async: true

  @now ~N[2026-09-26 12:00:00]

  for %{"locale" => locale, "seconds" => seconds, "words" => words} <-
        "test/fixtures/time_ago.json" |> File.read!() |> Jason.decode!() do
    @entry {locale, seconds, words}
    test "#{locale} #{seconds}s reads as Rails does" do
      {locale, seconds, words} = @entry
      assert DawarichWeb.TimeAgo.words(locale, NaiveDateTime.add(@now, -seconds), @now) == words
    end
  end
end
