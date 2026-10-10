defmodule Dawarich.TimeZoneOptionsTest do
  use ExUnit.Case, async: false

  alias Dawarich.TimeZoneOptions

  @corpus "test/fixtures/settings_corpus.json" |> File.read!() |> Jason.decode!()

  test "lists the committed Rails choices as {label, iana} in Rails' order" do
    list = TimeZoneOptions.list()

    assert hd(list) == {"(GMT-12:00) Etc/GMT+12", "Etc/GMT+12"}
    assert {"(GMT+09:00) Asia/Tokyo", "Asia/Tokyo"} in list
    assert list == Enum.map(@corpus["time_zone_options"], fn [label, iana] -> {label, iana} end)
  end

  test "a persistent_term list wins, so page tests can pin a short list" do
    :persistent_term.put(TimeZoneOptions, [{"x", "Etc/UTC"}])
    on_exit(fn -> :persistent_term.erase(TimeZoneOptions) end)

    assert TimeZoneOptions.list() == [{"x", "Etc/UTC"}]
  end
end
