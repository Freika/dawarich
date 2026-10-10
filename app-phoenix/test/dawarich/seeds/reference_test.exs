defmodule Dawarich.Seeds.ReferenceTest do
  use Dawarich.JobsCase

  alias Dawarich.A12hSeeds, as: Corpus
  alias Dawarich.Seeds.{Countries, Reference}

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(tags))

    on_exit(fn ->
      ScratchRepo.query!("ALTER TABLE tags DROP CONSTRAINT IF EXISTS a12h_tag_failure", [],
        log: false
      )
    end)

    :ok
  end

  test "region seed calls existing loader only for an empty table" do
    c = Corpus.case!("A12h_geometries")
    Corpus.load!(ScratchRepo, c["after"], ["countries"])
    Corpus.load!(ScratchRepo, %{}, ["regions"])
    path = region_asset!(c["sources"]["regions"])
    assert Reference.regions(ScratchRepo, asset: path, now: Corpus.now()) == :ok
    assert Corpus.snapshot(ScratchRepo, "regions") == c["after"]["regions"]
    assert rows("SELECT bool_and(ST_IsValid(geom)) FROM regions") == [[true]]
    assert Reference.regions(ScratchRepo, asset: "/absent") == :ok
    assert Corpus.snapshot(ScratchRepo, "regions") == c["after"]["regions"]

    partial = Corpus.case!("A12h_partial_tables")
    Corpus.load!(ScratchRepo, partial["seed"], ["regions"])
    assert Reference.regions(ScratchRepo, asset: path, now: Corpus.now()) == :ok
    assert Corpus.snapshot(ScratchRepo, "regions") == partial["after"]["regions"]
  end

  test "tags seed four defaults for scoped users only when all tags are absent" do
    for name <- [
          "A12h_multiple_users",
          "A12h_partial_tables",
          "A12h_later_user",
          "A12h_partial_tag_rerun"
        ] do
      c = Corpus.case!(name)
      Corpus.load!(ScratchRepo, c["seed"], ["tags", "users"])

      if c["seed"]["tags"] == [] do
        ScratchRepo.query!("SELECT setval(pg_get_serial_sequence('tags','id'),$1,false)", [
          hd(c["after"]["tags"])["id"]
        ])
      end

      assert Reference.tags(ScratchRepo, now: Corpus.now()) == :ok
      assert Corpus.snapshot(ScratchRepo, "tags") == c["after"]["tags"]
    end

    c = Corpus.case!("A12h_partial_tag_failure")
    Corpus.load!(ScratchRepo, c["seed"], ["tags", "users"])

    ScratchRepo.query!(
      "ALTER TABLE tags ADD CONSTRAINT a12h_tag_failure CHECK (name <> 'Favorite')"
    )

    error = assert_raise Postgrex.Error, fn -> Reference.tags(ScratchRepo, now: Corpus.now()) end
    assert error.postgres.constraint == "a12h_tag_failure"
    assert Corpus.snapshot(ScratchRepo, "tags") == c["after"]["tags"]
    assert Reference.tags(ScratchRepo, now: Corpus.now()) == :ok
    assert Corpus.snapshot(ScratchRepo, "tags") == c["after"]["tags"]
  end

  test "empty countries reject region seeds including an empty country FeatureCollection" do
    c = Corpus.case!("A12h_empty_countries")

    for load_empty <- [false, true] do
      Corpus.load!(ScratchRepo, c["after"], ["tags", "users", "countries", "regions"])

      if load_empty do
        priv = Corpus.country_priv!(c["sources"]["countries"])
        assert Countries.run(ScratchRepo, priv_dir: priv, now: Corpus.now()) == :ok
      end

      error =
        assert_raise Reference.MissingCountriesError, fn ->
          Reference.regions(ScratchRepo,
            asset: region_asset!(c["sources"]["regions"]),
            now: Corpus.now()
          )

          Reference.tags(ScratchRepo, now: Corpus.now())
        end

      assert error.message == c["error"]["message"]

      for table <- ~w(users countries regions tags) do
        assert Corpus.snapshot(ScratchRepo, table) == c["after"][table]
      end
    end
  end

  defp region_asset!(source) do
    path = Path.join(System.tmp_dir!(), "a12h-regions-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(source))
    on_exit(fn -> File.rm!(path) end)
    path
  end
end
