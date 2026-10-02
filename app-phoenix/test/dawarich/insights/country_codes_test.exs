defmodule Dawarich.Insights.CountryCodesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Insights.Details.CountryCodes
  alias Dawarich.{Redis, Repo}
  alias Dawarich.Test.{InsightsSeeds, TripsSeeds}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    InsightsSeeds.start_cache!()
  end

  test "the table reads like Ruby's to_h and is not cached by Phoenix" do
    for {name, code} <- [{"Germany", "DE"}, {"Czechia", "CZ"}, {"Germany", "D2"}],
        do: TripsSeeds.country!(name, code, code <> "X")

    assert CountryCodes.load() == [{"Germany", "D2"}, {"Czechia", "CZ"}]
    assert {:ok, nil} = Redis.cache_command(["GET", "countries_names_to_iso_a2"])
  end

  test "Rails' cached names are read in Ruby order without touching the table" do
    bytes = File.read!(Path.expand("../../fixtures/rails_cache/codec-hash.wire", __DIR__))
    InsightsSeeds.cache!("countries_names_to_iso_a2", bytes)
    TripsSeeds.country!("Germany", "DE", "DEU")
    pairs = CountryCodes.load()
    assert hd(pairs) == {"plan", "pro"}
    assert CountryCodes.lookup("plan", pairs) == "pro"
  end
end
