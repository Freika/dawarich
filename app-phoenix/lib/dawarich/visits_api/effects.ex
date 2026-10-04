defmodule Dawarich.VisitsApi.Effects do
  @moduledoc false

  alias Dawarich.RailsEffects

  @keys ~w(id user_id place_id area_id name status started_at ended_at duration deleted_at demo)a

  def load(repo, owner, id, active? \\ true) do
    active = if active?, do: " AND deleted_at IS NULL AND status!=2", else: ""

    case repo.query!(
           "SELECT #{Enum.join(@keys, ",")} FROM visits WHERE user_id=$1 AND id=$2#{active}",
           [owner, id]
         ).rows do
      [row] -> {:ok, Map.new(Enum.zip(@keys, row))}
      [] -> :not_found
    end
  end

  def changed(repo, old, new, now, adopt? \\ false) do
    if old && old.place_id && old.place_id != new.place_id,
      do: RailsEffects.orphan_places(repo, new.user_id, [old.place_id])

    if !new.demo do
      if old &&
           ((old.deleted_at != new.deleted_at && new.deleted_at != nil) ||
              (old.status != new.status && new.status == 2)),
         do: RailsEffects.orphan_places(repo, new.user_id, List.wrap(new.place_id))

      times =
        if old && old.started_at != new.started_at,
          do: [new.started_at, old.started_at],
          else: [new.started_at]

      RailsEffects.visit_months(
        repo,
        new.user_id,
        Enum.map(times, &DateTime.from_naive!(&1, "Etc/UTC"))
      )

      if adopt? && new.place_id, do: adopt(repo, new.place_id, now)
    end
  end

  defp adopt(repo, place, now) do
    case repo.query!(
           "UPDATE places SET demo=false,updated_at=$2 WHERE id=$1 AND demo=true RETURNING id",
           [place, now]
         ).rows do
      [[_]] ->
        repo.query!(
          "UPDATE tags SET demo=false,updated_at=$2 WHERE demo=true AND id IN (SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1)",
          [place, now]
        )

      [] ->
        :ok
    end
  end
end
