defmodule Dawarich.Visits.WebEffects do
  @moduledoc false
  alias Dawarich.{RailsEffects, TimeZoneName}
  alias Dawarich.Visits.WebScope

  def transact(repo, fun) do
    case repo.transaction(fn ->
           case fun.() do
             {:ok, result} -> result
             other -> repo.rollback(other)
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:error, result} -> result
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:replay, inspect(error.__struct__)}
  end

  def zone(repo, user, context) do
    setting = Map.get(user.settings, "timezone", "UTC")
    setting = if setting == "", do: "UTC", else: setting

    with {:ok, _} <-
           WebScope.day_bounds(setting, Date.to_iso8601(DateTime.to_date(context.now)), repo),
         do: {:ok, TimeZoneName.to_iana(setting)}
  end

  def single_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  def single_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:replay, "visit id"}
    end
  end

  def single_id(_), do: {:replay, "visit id"}

  def after_change(repo, user, old, new, _context) do
    RailsEffects.visit_months(repo, user.id, stamps([old, new]))
    previous = if old["place_id"] != new["place_id"], do: [old["place_id"]], else: []

    left =
      (new["status"] == 2 and old["status"] != 2) or
        (new["deleted_at"] != nil and old["deleted_at"] == nil)

    current = if left and not new["demo"], do: [new["place_id"]], else: []
    RailsEffects.orphan_places(repo, user.id, Enum.reject(previous ++ current, &is_nil/1))
  end

  def stamps(rows), do: Enum.map(rows, &DateTime.from_naive!(&1["started_at"], "Etc/UTC"))

  def persist(repo, old, new, now) do
    fields = ~w(name status place_id area_id started_at ended_at duration deleted_at)

    if Map.take(old, fields) != Map.take(new, fields) do
      repo.query!(
        "UPDATE visits SET name=$2,status=$3,place_id=$4,area_id=$5,started_at=$6,ended_at=$7,duration=$8,deleted_at=$9,updated_at=$10 WHERE id=$1",
        [old["id"] | Enum.map(fields, &new[&1])] ++ [DateTime.to_naive(now)],
        log: false
      )

      Map.put(new, "updated_at", DateTime.to_naive(now))
    else
      new
    end
  end

  def adopt(repo, old, new, now, explicit_adoption) do
    adopt_visit = explicit_adoption and new["demo"] and new["status"] != 2
    changed_place = old["place_id"] != new["place_id"]
    stamp = DateTime.to_naive(now)

    if adopt_visit,
      do:
        repo.query!("UPDATE visits SET demo=false,updated_at=$2 WHERE id=$1", [new["id"], stamp],
          log: false
        )

    if adopt_visit or (not new["demo"] and changed_place) do
      place =
        repo.query!("SELECT demo FROM places WHERE id=$1 FOR UPDATE", [new["place_id"]],
          log: false
        ).rows

      if adopt_visit or place == [[true]] do
        repo.query!(
          "UPDATE places SET demo=false,updated_at=$2 WHERE id=$1 AND demo=true",
          [new["place_id"], stamp],
          log: false
        )

        repo.query!(
          "UPDATE tags SET demo=false,updated_at=$2 WHERE demo=true AND id IN (SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1)",
          [new["place_id"], stamp],
          log: false
        )
      end
    end

    if adopt_visit, do: Map.merge(new, %{"demo" => false, "updated_at" => stamp}), else: new
  end
end
