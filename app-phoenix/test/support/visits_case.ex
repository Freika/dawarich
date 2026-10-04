defmodule Dawarich.VisitsCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  import Dawarich.JobsCase, only: [rows: 2]

  alias Dawarich.{ScratchRepo, Wave5bFixtures}

  @dir "test/fixtures/visits"
  @visit_keys ~w(id user_id area_id place_id started_at ended_at duration name status confidence
                 confidence_breakdown detection_version demo import_id deleted_at)
  @visit_sql "SELECT id, user_id, area_id, place_id, floor(extract(epoch FROM started_at))::bigint, " <>
               "floor(extract(epoch FROM ended_at))::bigint, duration, name, status, confidence, " <>
               "confidence_breakdown::text, detection_version, demo, import_id, deleted_at IS NOT NULL " <>
               "FROM visits WHERE user_id = $1 ORDER BY started_at, id"
  @place_keys ~w(user_id name latitude longitude lonlat_wkt city country source import_id demo note geodata
                 name_locked_at reverse_geocoded_at)
  @place_sql "SELECT user_id, name, latitude::text, longitude::text, ST_AsText(lonlat), city, country, source, " <>
               "import_id, demo, note, geodata::text, name_locked_at IS NOT NULL, " <>
               "reverse_geocoded_at IS NOT NULL FROM places WHERE user_id = $1 ORDER BY id"
  @claims_sql "SELECT p.timestamp, floor(extract(epoch FROM v.started_at))::bigint FROM points p " <>
                "LEFT JOIN visits v ON v.id = p.visit_id WHERE p.user_id = $1 ORDER BY p.timestamp, p.id"

  using do
    quote do
      use Dawarich.GeocodingCase
      import Dawarich.VisitsCase
    end
  end

  def visits_fixture(name), do: Wave5bFixtures.read!(Path.join(@dir, name <> ".json"))

  def load_visits!(name),
    do: Wave5bFixtures.load!(ScratchRepo, Path.join(@dir, name <> ".json")).fixture

  def detection_fixture_names do
    @dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.filter(&Map.has_key?(Wave5bFixtures.read!(&1), "stages"))
    |> Enum.map(&Path.basename(&1, ".json"))
  end

  def user_id(f), do: hd(f["input"]["users"])["id"]

  def run_args(f), do: %{"time_zone" => f["run"]["time_zone"], "plan_restricted" => false}

  def visits(user_id) do
    for row <- rows(@visit_sql, [user_id]) do
      @visit_keys |> Enum.zip(row) |> Map.new() |> Map.update!("deleted_at", &if(&1, do: "set"))
    end
  end

  def comparable_visits(visits, place_key) do
    visits
    |> Enum.map(
      &(&1
        |> Map.delete("id")
        |> Map.update!("place_id", fn id -> Map.fetch!(place_key, id) end))
    )
    |> Enum.sort_by(&{&1["started_at"], &1["name"]})
  end

  def actual_place_keys do
    for [id, name, wkt] <- rows("SELECT id, name, ST_AsText(lonlat) FROM places", []),
        into: %{nil => nil},
        do: {id, {name, wkt}}
  end

  def expected_place_keys(f) do
    for p <- (f["input"]["places"] || []) ++ f["expected"]["places"],
        into: %{nil => nil},
        do: {p["id"], {p["name"], p["lonlat_wkt"]}}
  end

  def places(user_id) do
    for row <- rows(@place_sql, [user_id]), do: @place_keys |> Enum.zip(row) |> Map.new()
  end

  def expected_places(places) do
    places
    |> Enum.map(fn p ->
      p
      |> Map.take(@place_keys)
      |> Map.update!("name_locked_at", &(&1 != nil))
      |> Map.update!("reverse_geocoded_at", &(&1 != nil))
    end)
  end

  def tags(user_id),
    do:
      rows(
        "SELECT user_id, name, color, privacy_radius_meters, demo FROM tags WHERE user_id = $1 ORDER BY id",
        [user_id]
      )

  def expected_tags(tags),
    do:
      Enum.map(
        tags,
        &[&1["user_id"], &1["name"], &1["color"], &1["privacy_radius_meters"], &1["demo"]]
      )

  def point_claims(user_id), do: rows(@claims_sql, [user_id])

  def effects(place_key) do
    kinds = Dawarich.GeocodingCase.kinds()

    %{
      "visit_months" =>
        kinds
        |> payloads("visit_months_changed", "started_at")
        |> Enum.map(&String.slice(&1, 0, 7))
        |> uniq_sort(),
      "orphan_place_ids" =>
        kinds |> payloads("places_delete_if_orphan", "place_ids") |> uniq_sort(),
      "reverse_geocode_place_ids" => payloads(kinds, "reverse_geocode_place", "place_id"),
      "place_name_fetch_ids" =>
        kinds |> payloads("place_name_fetch", "place_id") |> Enum.map(&Map.fetch!(place_key, &1))
    }
  end

  def expected_effects(effects, place_key),
    do:
      Map.update!(
        effects,
        "place_name_fetch_ids",
        &Enum.map(&1, fn id -> Map.fetch!(place_key, id) end)
      )

  def rails_commands_count, do: hd(hd(rows("SELECT count(*) FROM phoenix.rails_commands", [])))

  defp payloads(kinds, kind, key) do
    for %{"kind" => ^kind, "payload" => payload} <- kinds,
        value <- List.wrap(payload[key]),
        do: value
  end

  defp uniq_sort(values), do: values |> Enum.uniq() |> Enum.sort()
end
