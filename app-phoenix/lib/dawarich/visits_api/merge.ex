defmodule Dawarich.VisitsApi.Merge do
  @moduledoc false

  alias Dawarich.{I18n, Jobs, RailsTime, RubyInteger}
  alias Dawarich.VisitsApi.Effects

  def call(owner, ids, zone, now, repo \\ Jobs.repo()) do
    RailsTime.with_zone(repo, zone, fn ->
      with {:ok, ids} <- ids(ids),
           {:ok, visits} <- visits(repo, owner, ids) do
        merge(repo, visits, DateTime.to_naive(now))
      end
    end)
  end

  defp ids(ids) when is_list(ids) and length(ids) < 2,
    do: error(422, "at_least_2_visits_must_be_selected_for_merging")

  defp ids(nil), do: error(422, "at_least_2_visits_must_be_selected_for_merging")

  defp ids(ids) when is_list(ids) do
    if Enum.all?(ids, &(is_integer(&1) || is_binary(&1))),
      do:
        {:ok, Enum.map(ids, fn id -> if is_integer(id), do: id, else: RubyInteger.to_i(id) end)},
      else: {:replay, "visit merge id shape"}
  end

  defp ids(_), do: {:replay, "visit merge root shape"}

  defp visits(repo, owner, ids) do
    rows =
      repo.query!(
        "SELECT id FROM visits WHERE user_id=$1 AND id=ANY($2) AND deleted_at IS NULL AND status!=2 ORDER BY started_at",
        [owner, ids]
      ).rows

    if length(rows) == length(ids),
      do:
        {:ok,
         Enum.map(rows, fn [id] ->
           {:ok, row} = Effects.load(repo, owner, id)
           row
         end)},
      else: error(404, "one_or_more_visits_not_found")
  end

  defp merge(repo, [base | rest] = visits, now) do
    latest = visits |> Enum.map(& &1.ended_at) |> Enum.max(NaiveDateTime)
    duration = round(NaiveDateTime.diff(latest, base.started_at, :microsecond) / 60_000_000)

    repo.query!(
      "UPDATE visits SET ended_at=$2,duration=$3,name=$4,status=1,updated_at=$5 WHERE id=$1",
      [base.id, latest, duration, name(visits), now]
    )

    {:ok, new} = Effects.load(repo, base.user_id, base.id)
    Effects.changed(repo, base, new, now)
    ids = Enum.map(rest, & &1.id)
    repo.query!("UPDATE points SET visit_id=$1 WHERE visit_id=ANY($2)", [base.id, ids])
    repo.query!("DELETE FROM place_visits WHERE visit_id=ANY($1)", [ids])

    repo.query!("DELETE FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1)", [ids])

    repo.query!("DELETE FROM visits WHERE id=ANY($1)", [ids])
    Enum.each(rest, &Effects.changed(repo, &1, %{&1 | deleted_at: now}, now))
    {:ok, new}
  end

  defp name([base | _] = visits) do
    places = Enum.map(visits, & &1.place_id)

    if Enum.all?(places, &(!is_nil(&1))) && length(Enum.uniq(places)) == 1 do
      base.name
    else
      {_, names} =
        Enum.reduce(visits, {MapSet.new(), []}, fn visit, {seen, names} ->
          key = visit.name |> String.trim() |> String.downcase()

          if key == "" || MapSet.member?(seen, key),
            do: {seen, names},
            else: {MapSet.put(seen, key), names ++ [visit.name]}
        end)

      if names == [], do: base.name, else: Enum.join(names, ", ")
    end
  end

  defp error(status, key), do: {:error, status, I18n.en!("controllers.api.v1.visits." <> key)}
end
