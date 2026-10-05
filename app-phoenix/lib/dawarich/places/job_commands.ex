defmodule Dawarich.Places.JobCommands do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands

  def name_fetch(repo, user, place),
    do:
      resolve(repo, "places.name_fetch", fn
        :oban ->
          leaf(repo, "places.name_fetch", user, place)

        :sidekiq ->
          RailsCommands.insert!(repo, "place_name_fetch", %{
            "user_id" => user,
            "place_id" => place
          })
      end)

  def orphan_places(repo, user, ids),
    do:
      resolve(repo, "places.delete_if_orphan", fn
        :oban ->
          Enum.each(Enum.uniq(ids), &leaf(repo, "places.delete_if_orphan", user, &1))

        :sidekiq ->
          RailsCommands.insert!(repo, "places_delete_if_orphan", %{
            "user_id" => user,
            "place_ids" => Enum.uniq(ids)
          })
      end)

  def orphan_cleanup(repo, user),
    do:
      resolve(repo, "places.orphan_cleanup", fn
        :oban -> publish(repo, "places.orphan_cleanup", %{"user_id" => user}, user)
        :sidekiq -> RailsCommands.insert!(repo, "places_orphan_cleanup", %{"user_id" => user})
      end)

  def bulk_name_fetch(repo),
    do:
      resolve(repo, "places.bulk_name_fetch", fn
        :oban -> publish(repo, "places.bulk_name_fetch", %{}, nil)
        :sidekiq -> RailsCommands.insert!(repo, "places_bulk_name_fetch", %{})
      end)

  defp resolve(repo, type, fun) do
    {:ok, _} = repo.transaction(fn -> fun.(Ownership.lock(repo, "command:" <> type)) end)
    :ok
  end

  defp leaf(repo, type, user, place) do
    if repo.query!("SELECT 1 FROM places WHERE id=$1 AND user_id=$2", [place, user], log: false).num_rows ==
         1 do
      publish(repo, type, %{"user_id" => user, "place_id" => place}, place)
    end

    :ok
  end

  defp publish(repo, type, payload, aggregate) do
    repo.query!(
      "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6)",
      [
        Ecto.UUID.bingenerate(),
        type,
        payload,
        aggregate,
        %{"producer" => "phoenix.places"},
        DateTime.utc_now()
      ],
      log: false
    )

    :ok
  end
end
