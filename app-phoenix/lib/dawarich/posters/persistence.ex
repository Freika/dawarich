defmodule Dawarich.Posters.Persistence do
  @moduledoc false
  alias Dawarich.Repo
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Posters.Command

  @settings ~w(title lat lon distance theme start_at end_at source route_fill route_opacity route_width)

  def delete(id, user, repo \\ Repo) do
    repo.transaction(fn ->
      owner = Command.owner(repo)

      case repo.query!("SELECT id FROM posters WHERE id=$1 AND user_id=$2 FOR UPDATE", [
             id,
             user.id
           ]).rows do
        [] ->
          repo.rollback(:missing)

        [[^id]] ->
          blobs =
            repo.query!(
              "DELETE FROM active_storage_attachments WHERE record_type='Poster' AND record_id=$1 RETURNING blob_id",
              [id]
            ).rows
            |> List.flatten()
            |> Enum.uniq()

          repo.query!("DELETE FROM posters WHERE id=$1 AND user_id=$2", [id, user.id])

          if blobs != [] do
            if owner == :oban do
              Dawarich.Exports.PurgeWorker.enqueue!(repo, blobs)
            else
              Command.purge(repo, owner, %{
                "poster_id" => id,
                "user_id" => user.id,
                "blob_ids" => blobs
              })
            end
          end

          id
      end
    end)
  end

  def create(params, %{id: user_id} = user, locale, repo \\ Repo) do
    params =
      Map.filter(params, fn {_, value} ->
        is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)
      end)

    name =
      if Ruby.blank?(params["name"]),
        do: DawarichWeb.Translate.t(locale, "controllers.posters.untitled", %{}),
        else: Ruby.to_s(params["name"])

    now = NaiveDateTime.utc_now()

    repo.transaction(fn ->
      owner = Command.owner(repo)

      %{rows: [[id]]} =
        repo.query!(
          "INSERT INTO posters (name, status, settings, user_id, created_at, updated_at) VALUES ($1, 0, $2, $3, $4, $4) RETURNING id",
          [name, Map.take(params, @settings), user_id, now],
          log: false
        )

      Command.produce(repo, owner, id, user, locale, now)
      id
    end)
  rescue
    error -> {:error, "poster write failed: " <> inspect(error.__struct__)}
  end
end
