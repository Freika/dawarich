defmodule Dawarich.Insights.CountryCodesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Insights.Details.CountryCodes
  alias Dawarich.{Redis, Repo}
  alias Dawarich.Test.{InsightsSeeds, TripsSeeds}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    InsightsSeeds.start_cache!()
  end

  test "warm country hash stays authoritative and cold fallback preserves ordered duplicate and fuzzy behavior" do
    oracle =
      Path.expand("../../fixtures/a12d1b4/cache.json", __DIR__) |> File.read!() |> Jason.decode!()

    source = oracle["fragments"]
    key = source["country_key"]
    assert key == "countries_names_to_iso_a2"
    for code <- ~w(AA BB), do: TripsSeeds.country!("Duplicate", code, code <> "X")
    expected = Enum.map(source["country_pairs"], &List.to_tuple/1)
    assert CountryCodes.load() == expected
    assert CountryCodes.lookup("duplicate region", expected) == "BB"
    assert CountryCodes.lookup("DUPLICATE", expected) == "BB"
    assert CountryCodes.lookup("missing", expected) == nil
    assert CountryCodes.lookup("Duplicate", [{"Duplicate", nil}]) == nil
    bytes = File.read!(Path.expand("../../fixtures/rails_cache/codec-hash.wire", __DIR__))
    <<0, 17, type, _expires::little-float-64, rest::binary>> = bytes
    expires = (System.os_time(:second) + source["country_ttl"]) * 1.0
    bytes = <<0, 17, type, expires::little-float-64, rest::binary>>
    assert {:ok, "OK"} = Redis.cache_command(["SET", key, bytes, "EX", source["country_ttl"]])
    warm = CountryCodes.load()
    assert hd(warm) == {"plan", "pro"}
    Repo.query!("UPDATE countries SET iso_a2='CC' WHERE iso_a2='BB'", [])
    assert CountryCodes.load() == warm
    assert CountryCodes.lookup("PLAN", warm) == "pro"
    assert {:ok, ttl} = Redis.cache_command(["TTL", key])
    assert ttl > 86_390 and ttl <= source["country_ttl"]
    assert {:ok, 1} = Redis.cache_command(["DEL", key])
    assert CountryCodes.load() == [{"Duplicate", "CC"}]
    InsightsSeeds.cache!(key, Dawarich.RailsCache.Wire.encode_boolean(nil, expires_at: nil))
    assert CountryCodes.load() == [{"Duplicate", "CC"}]
    assert CountryCodes.lookup("alpha", [{"alpha region", nil}, {"alpha place", "AP"}]) == nil
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
