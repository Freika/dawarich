defmodule Dawarich.Seeds.CountriesTest do
  use Dawarich.JobsCase

  alias Dawarich.A12hSeeds, as: Corpus
  alias Dawarich.Seeds.Countries

  test "empty country table loads source geometries and nonempty table stays untouched" do
    for name <- ["A12h_geometries", "A12h_partial_tables"] do
      c = Corpus.case!(name)
      Corpus.load!(ScratchRepo, c["seed"], ["countries"])
      priv = Corpus.country_priv!(c["sources"]["countries"])
      assert Countries.run(ScratchRepo, priv_dir: priv, now: Corpus.now()) == :ok
      assert Corpus.snapshot(ScratchRepo, "countries") == c["after"]["countries"]
      assert Countries.run(ScratchRepo, priv_dir: "/absent", now: Corpus.now()) == :ok
      assert Corpus.snapshot(ScratchRepo, "countries") == c["after"]["countries"]
    end

    Corpus.load!(ScratchRepo, %{}, ["countries"])
    assert Countries.run(ScratchRepo, now: Corpus.now()) == :ok
    assert [[count]] = rows("SELECT count(*) FROM countries")
    assert count > 200
  end

  test "invalid country rolls back the source load" do
    c = Corpus.case!("A12h_country_failure")
    Corpus.load!(ScratchRepo, c["seed"], ["countries"])
    priv = Corpus.country_priv!(c["sources"]["countries"])

    error =
      assert_raise ArgumentError, fn ->
        Countries.run(ScratchRepo, priv_dir: priv, now: Corpus.now())
      end

    assert error.message == c["error"]["message"]
    assert Corpus.snapshot(ScratchRepo, "countries") == c["after"]["countries"]

    valid = Corpus.case!("A12h_geometries")["sources"]["countries"]
    [first, second] = valid["features"]

    for geometry <- [
          nil,
          %{"type" => "Polygon", "coordinates" => []},
          %{"type" => "Unknown", "coordinates" => []}
        ] do
      source = %{valid | "features" => [first, %{second | "geometry" => geometry}]}
      priv = Corpus.country_priv!(source)

      assert_raise ArgumentError, fn ->
        Countries.run(ScratchRepo, priv_dir: priv, now: Corpus.now())
      end

      assert Corpus.snapshot(ScratchRepo, "countries") == []
    end
  end
end
