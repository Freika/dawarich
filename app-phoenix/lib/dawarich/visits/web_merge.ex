defmodule Dawarich.Visits.WebMerge do
  @moduledoc false
  alias Dawarich.{RailsEffects, RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Visits.{WebEffects, WebScope}

  def run(repo, user, raw_ids, context) do
    with {:ok, ids} <- WebScope.ids(raw_ids, :infinity),
         :ok <- minimum(ids),
         {:ok, zone} <- WebEffects.zone(repo, user, context) do
      WebEffects.transact(repo, fn ->
        with {:ok, selected} <- WebScope.load(repo, user, ids, context.now, context.self_hosted),
             :ok <- same_day(repo, selected, zone),
             :ok <- graph(repo, ids),
             ordered <-
               Enum.sort_by(
                 selected,
                 &{NaiveDateTime.to_gregorian_seconds(&1["started_at"]), &1["id"]}
               ),
             {:ok, name} <- name(ordered) do
          merge(
            repo,
            user,
            ordered,
            name,
            zone,
            context
          )
        end
      end)
    end
  end

  defp minimum(ids) when length(ids) >= 2, do: :ok
  defp minimum(_ids), do: {:error, :select_visits_to_merge}

  defp same_day(repo, rows, zone) do
    if length(WebEffects.dates(repo, rows, zone)) == 1,
      do: :ok,
      else: {:error, :visits_must_share_day}
  end

  defp graph(repo, ids) do
    if Dawarich.Jobs.Ownership.lock(repo, "command:visits.suggest") == :oban or
         repo.query!(
           "SELECT 1 FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1) LIMIT 1",
           [ids],
           log: false
         ).num_rows == 0,
       do: :ok,
       else: {:replay, "noted visit merge requires Rails dependent deletion"}
  end

  defp name([base | _] = rows) do
    places = Enum.map(rows, & &1["place_id"])

    if Enum.all?(places, &(not is_nil(&1))) and length(Enum.uniq(places)) == 1 do
      {:ok, base["name"]}
    else
      {_seen, names} =
        Enum.reduce(rows, {MapSet.new(), []}, fn row, {seen, names} ->
          key = Dawarich.Visits.NameKey.build(row["name"])

          if key == "" or MapSet.member?(seen, key),
            do: {seen, names},
            else: {MapSet.put(seen, key), names ++ [row["name"]]}
        end)

      {:ok, if(names == [], do: base["name"], else: Enum.join(names, ", "))}
    end
  end

  defp merge(repo, user, [base | sources] = rows, name, zone, context) do
    last = rows |> Enum.map(& &1["ended_at"]) |> Enum.max(NaiveDateTime)

    duration =
      RubyFloat.round(NaiveDateTime.diff(last, base["started_at"], :microsecond) / 60_000_000)

    if Ruby.blank?(name) or duration < 0 or NaiveDateTime.compare(last, base["started_at"]) != :gt do
      {:replay, "legacy visit merge validation"}
    else
      new =
        Map.merge(base, %{
          "name" => name,
          "ended_at" => last,
          "duration" => duration,
          "status" => 1
        })

      with :ok <- WebEffects.validate(new) do
        new = WebEffects.persist(repo, base, new, context.now)
        source_ids = Enum.map(sources, & &1["id"])

        repo.query!(
          "UPDATE points SET visit_id=$2,lock_version=coalesce(lock_version,0)+1 WHERE visit_id=ANY($1)",
          [source_ids, base["id"]],
          log: false
        )

        repo.query!("DELETE FROM place_visits WHERE visit_id=ANY($1)", [source_ids], log: false)

        repo.query!(
          "DELETE FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1)",
          [source_ids],
          log: false
        )

        repo.query!("DELETE FROM visits WHERE id=ANY($1)", [source_ids], log: false)
        WebEffects.months(repo, user, rows ++ [new])

        RailsEffects.orphan_places(
          repo,
          user.id,
          sources
          |> Enum.reject(& &1["demo"])
          |> Enum.map(& &1["place_id"])
          |> Enum.reject(&is_nil/1)
        )

        {:ok, %{visit: new, source_ids: source_ids, rows: rows, zone: zone}}
      end
    end
  end
end
