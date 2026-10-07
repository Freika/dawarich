defmodule Dawarich.Transportation.UserReclassify do
  @moduledoc false
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Transportation.{RecalculationFence, RecalculationStatus}

  def run(repo, %{"user_id" => user, "event_id" => event}, ctx) do
    result =
      repo.transaction(fn ->
        if Processed.claim!(repo, event, "transportation.user_reclassify") do
          case repo.query!(
                 "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
                 [user]
               ).rows do
            [] ->
              RecalculationFence.release(repo, user, event)
              :missing

            [[settings]] ->
              settings = Dawarich.UserSettings.safe(settings)

              if Ownership.lock(repo, "command:transportation.reclassify_track") != :oban,
                do: repo.rollback(:source_owner)

              ids =
                repo.query!("SELECT id FROM tracks WHERE user_id=$1 ORDER BY id", [user]).rows
                |> List.flatten()

              Dawarich.AfterCommit.cache(repo, "transport_start", %{
                "user_id" => user,
                "track_ids" => ids,
                "now" => DateTime.to_iso8601(ctx.now),
                "event_id" => event,
                "locale" => settings["locale"],
                "time_zone" => settings["timezone"]
              })

              {:started, length(ids)}
          end
        else
          :duplicate
        end
      end)

    case result do
      {:ok, {:started, _total}} ->
        :ok

      {:ok, _} ->
        :ok

      {:error, reason} ->
        RecalculationFence.release(repo, user, event)
        RecalculationStatus.fail(user, ctx.now, inspect(reason))
        {:error, reason}
    end
  rescue
    error ->
      RecalculationFence.release(repo, user, event)
      RecalculationStatus.fail(user, ctx.now, Exception.message(error))
      reraise error, __STACKTRACE__
  end
end
