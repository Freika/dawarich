defmodule Dawarich.ReleaseOperations.PlaceNameLocksTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.ReleaseOperations.{PlaceNameLocks, PlaceNames}
  alias Dawarich.Wave6Fixtures

  @zoo %{
    "name" => "Zoo Leipzig",
    "street" => "Pfaffendorfer Straße",
    "housenumber" => "29",
    "postcode" => "04105",
    "city" => "Leipzig",
    "state" => "Sachsen",
    "osm_value" => "zoo"
  }
  @locked_at ~N[2020-06-01 10:00:00.000000]

  setup do
    Wave6Fixtures.reset!()
    %{user: Wave6Fixtures.user!()}
  end

  test "machine names match Rails for every fixture case" do
    cases = Wave6Fixtures.load!("extractors")["place_names"]

    assert cases != []

    for %{"properties" => properties, "built" => built, "geocoder" => geocoder} <- cases do
      assert {properties, PlaceNames.built_name(properties)} == {properties, built}
      assert {properties, PlaceNames.geocoder_name(properties)} == {properties, geocoder}
    end
  end

  test "locks user-named places and skips machine-named, default and locked ones", %{user: user} do
    built = place!(user, "Zoo Leipzig, Pfaffendorfer Straße, 29, Leipzig, Sachsen", @zoo)
    geocoder = place!(user, "Zoo Leipzig (Zoo)", @zoo)
    custom = place!(user, "My favourite café", @zoo)
    default = place!(user, "Suggested place", %{"city" => "Leipzig"})
    locked = place!(user, "Home", @zoo, @locked_at)

    assert PlaceNameLocks.run(ScratchRepo) == :ok

    assert locks([built, geocoder, default]) == [nil, nil, nil]
    assert [%NaiveDateTime{}] = locks([custom])
    assert locks([locked]) == [@locked_at]
  end

  test "a float in a used property counts as not machine-named", %{user: user} do
    place = place!(user, "Zoo Leipzig (Zoo)", %{@zoo | "housenumber" => 29.5})

    assert PlaceNameLocks.run(ScratchRepo) == :ok

    assert [%NaiveDateTime{}] = locks([place])
  end

  test "the sweep pages past a full batch of 1,000 by id", %{user: user} do
    rows(
      """
      INSERT INTO places (name, user_id, latitude, longitude, geodata, created_at, updated_at)
      SELECT 'Custom ' || g, $1, 51.3497, 12.3694, '{"properties": {}}', now(), now()
      FROM generate_series(1, 1001) g
      """,
      [user]
    )

    assert PlaceNameLocks.perform(%Oban.Job{args: %{"version" => 1}}) == :ok

    assert rows("SELECT count(*) FROM places WHERE name_locked_at IS NULL") == [[0]]
  end

  test "perform cancels an unsupported version" do
    assert PlaceNameLocks.perform(%Oban.Job{args: %{"version" => 2}}) ==
             {:cancel, :unsupported_version}
  end

  defp place!(user, name, properties, locked_at \\ nil) do
    now = NaiveDateTime.utc_now()

    Wave6Fixtures.insert!("places", %{
      "name" => name,
      "user_id" => user,
      "latitude" => Decimal.new("51.349700"),
      "longitude" => Decimal.new("12.369400"),
      "geodata" => %{"properties" => properties},
      "name_locked_at" => locked_at,
      "created_at" => now,
      "updated_at" => now
    })
  end

  defp locks(ids) do
    Enum.map(ids, fn id ->
      [[locked_at]] = rows("SELECT name_locked_at FROM places WHERE id = $1", [id])
      locked_at
    end)
  end
end
