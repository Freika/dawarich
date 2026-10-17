defmodule Dawarich.EnhancedImport.ItemWriter do
  @moduledoc false
  alias Dawarich.EnhancedImport.{Adapters, Deadline, PlaceWriter, TrackWriter}

  def reduce(repo, import, path, context, deadline) do
    initial = %{places: PlaceWriter.new(import), counts: %{}}
    guard = Map.fetch!(import, :fence)
    unless trust?(import), do: guard.(fn -> TrackWriter.reset(repo, import) end)

    Adapters.reduce(path, import, context, initial, fn item, state ->
      Deadline.check!(deadline)
      state = guard.(fn -> write(repo, import, item, state) end)
      if callback = context[:on_item], do: callback.(item)
      state
    end).counts
  end

  defp write(repo, import, %{"started_at" => first, "place" => place} = item, state) do
    state = place(repo, state, place)
    id = state.places.last_id
    start = naive(first)
    stop = naive(item["ended_at"])

    if id && NaiveDateTime.compare(stop, start) == :gt do
      result =
        repo.query!(
          "INSERT INTO visits(user_id,import_id,place_id,started_at,ended_at,duration,name,status,created_at,updated_at) SELECT $1,$2,$3,$4,$5,$6,$7,0,now(),now() WHERE NOT EXISTS(SELECT 1 FROM visits WHERE user_id=$1 AND place_id=$3 AND started_at=$4) ON CONFLICT DO NOTHING RETURNING id",
          [
            import.user_id,
            import.id,
            id,
            start,
            stop,
            round(NaiveDateTime.diff(stop, start) / 60),
            item["name"] || place["name"]
          ],
          log: false
        )

      if result.rows != [] do
        adopt(repo, import.user_id, id)

        Dawarich.RailsEffects.visit_months(repo, import.user_id, [
          DateTime.from_naive!(start, "Etc/UTC")
        ])
      end

      bump(state, "visits")
    else
      state
    end
  end

  defp write(repo, import, %{"tracker_id" => _} = item, state) do
    case TrackWriter.upsert(repo, import, item, trust?(import)) do
      nil ->
        state

      {_id, segments} ->
        state = bump(state, "tracks")

        if segments > 0,
          do: %{state | counts: Map.update(state.counts, "segments", segments, &(&1 + segments))},
          else: state
    end
  end

  defp write(repo, _import, item, state), do: place(repo, state, item)

  defp place(repo, state, item) do
    keys = ~w(external_place_id name latitude longitude semantic_type tag_name tag_color)a
    place = Map.new(keys, &{&1, item[Atom.to_string(&1)]})
    places = PlaceWriter.upsert(repo, %{state.places | last_id: nil}, place)
    state = %{state | places: places}
    if places.last_id, do: bump(state, "places"), else: state
  end

  defp bump(state, key), do: %{state | counts: Map.update(state.counts, key, 1, &(&1 + 1))}

  defp adopt(repo, user, place) do
    adopted =
      repo.query!(
        "UPDATE places SET demo=false,updated_at=now() WHERE id=$1 AND user_id=$2 AND demo RETURNING id",
        [place, user],
        log: false
      ).rows

    if adopted != [] do
      repo.query!(
        "UPDATE tags SET demo=false,updated_at=now() WHERE user_id=$2 AND demo AND id IN(SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1)",
        [place, user],
        log: false
      )
    end
  end

  defp naive(text), do: text |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp trust?(import),
    do:
      get_in(import.data, ["options", "trust_source"]) not in [false, nil] or
        not Map.has_key?(import.data["options"] || %{}, "trust_source")
end
