defmodule Dawarich.UserData.Restore.PointRefs do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Ingest.Ruby

  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

  def load(repo, user) do
    imports =
      repo.query!(
        "SELECT id,name,source,to_char(created_at,'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') FROM imports WHERE user_id=$1 ORDER BY id",
        [user],
        log: false
      ).rows

    countries =
      repo.query!("SELECT id,name,iso_a2,iso_a3 FROM countries ORDER BY id", [], log: false).rows

    visits =
      repo.query!(
        "SELECT id,name,to_char(started_at,'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'),to_char(ended_at,'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') FROM visits WHERE user_id=$1 ORDER BY id",
        [user],
        log: false
      ).rows

    %{
      imports:
        Map.new(
          for [id, name, source, created] <- imports,
              key <- [source, source_name(source)],
              do: {[name, key, created], id}
        ),
      countries:
        Map.new(
          Enum.flat_map(countries, fn [id, name, a2, a3] -> [{[name, a2, a3], id}, {name, id}] end)
        ),
      visits: Map.new(visits, fn [id, name, start, finish] -> {[name, start, finish], id} end)
    }
  end

  defp source_name(source) when is_integer(source), do: Enum.at(@sources, source)
  defp source_name(source), do: source

  def resolve(row, original, refs, context) do
    row
    |> import_ref(original["import_reference"], refs, context)
    |> country_ref(original["country_info"], refs)
    |> visit_ref(original["visit_reference"], refs, context)
  end

  defp import_ref(row, ref, refs, context) when is_map(ref) do
    put_found(
      row,
      "import_id",
      refs.imports[[ref["name"], ref["source"], timestamp(ref["created_at"], context)]]
    )
  end

  defp import_ref(row, _, _, _), do: row

  defp country_ref(row, ref, refs) when is_map(ref) do
    id =
      refs.countries[[ref["name"], ref["iso_a2"], ref["iso_a3"]]] ||
        (Ruby.present?(ref["name"]) && refs.countries[ref["name"]])

    put_found(row, "country_id", id)
  end

  defp country_ref(row, _, _), do: row

  defp visit_ref(row, ref, refs, context) when is_map(ref) do
    put_found(
      row,
      "visit_id",
      refs.visits[
        [ref["name"], timestamp(ref["started_at"], context), timestamp(ref["ended_at"], context)]
      ]
    )
  end

  defp visit_ref(row, _, _, _), do: row
  defp put_found(row, key, id), do: if(id, do: Map.put(row, key, id), else: row)

  defp timestamp(value, context) do
    case Batch.row!(context.repo, "imports", %{"created_at" => value}, context)["created_at"] do
      nil -> value
      time -> String.slice(time, 0, 19) <> "Z"
    end
  end
end
