defmodule Dawarich.Places.WebDelete do
  @moduledoc false
  alias Dawarich.PlaceCascade

  def run(repo, user, id, _context) do
    repo.transaction(fn ->
      case repo.query!(
             "SELECT id FROM places WHERE id=$1 AND user_id=$2 FOR UPDATE",
             [id, user.id],
             log: false
           ).rows do
        [] ->
          {:error, :not_found}

        [[^id]] ->
          repo.query!(
            "SELECT id FROM notes WHERE attachable_type='Place' AND attachable_id=$1 FOR UPDATE",
            [id],
            log: false
          )

          if unsupported?(repo, id) do
            {:replay, "place dependent content graph"}
          else
            PlaceCascade.delete!(repo, [id])
            {:ok, id}
          end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp unsupported?(repo, id) do
    [[unsupported]] =
      repo.query!(
        "SELECT EXISTS (SELECT 1 FROM action_text_rich_texts WHERE (record_type='Place' AND record_id=$1) OR (record_type='Note' AND record_id IN (SELECT id FROM notes WHERE attachable_type='Place' AND attachable_id=$1))) OR EXISTS (SELECT 1 FROM active_storage_attachments WHERE (record_type='Place' AND record_id=$1) OR (record_type='Note' AND record_id IN (SELECT id FROM notes WHERE attachable_type='Place' AND attachable_id=$1)))",
        [id],
        log: false
      ).rows

    unsupported
  end
end
