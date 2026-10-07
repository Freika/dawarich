defmodule Dawarich.Transportation.UserReclassify do
  @moduledoc false
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Transportation.RecalculationStatus

  def run(repo, %{"user_id" => user, "event_id" => event}, ctx) do
    result =
      repo.transaction(fn ->
        if Processed.claim!(repo, event, "transportation.user_reclassify") do
          case repo.query!(
                 "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
                 [user]
               ).rows do
            [] ->
              :missing

            [[settings]] ->
              settings = Dawarich.UserSettings.safe(settings)

              if Ownership.lock(repo, "command:transportation.reclassify_track") != :oban,
                do: repo.rollback(:source_owner)

              ids =
                repo.query!("SELECT id FROM tracks WHERE user_id=$1 ORDER BY id", [user]).rows
                |> List.flatten()

              RecalculationStatus.start(user, length(ids), ctx.now)
              Map.get(ctx, :before_enqueue, fn -> :ok end).()

              ids
              |> Enum.chunk_every(100)
              |> Enum.with_index()
              |> Enum.each(fn {slice, index} ->
                Enum.each(slice, fn id ->
                  payload = %{"track_id" => id, "report_progress" => true, "user_id" => user}

                  metadata = %{
                    "producer" => "Phoenix UserReclassify",
                    "parent_event_id" => event,
                    "locale" => settings["locale"],
                    "time_zone" => settings["timezone"]
                  }

                  repo.query!(
                    "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,'transportation.reclassify_track',1,$2,$3,$4,$5)",
                    [
                      Ecto.UUID.bingenerate(),
                      payload,
                      metadata,
                      id,
                      DateTime.add(ctx.now, index * 10)
                    ]
                  )
                end)
              end)

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
        RecalculationStatus.fail(user, ctx.now, inspect(reason))
        {:error, reason}
    end
  rescue
    error ->
      RecalculationStatus.fail(user, ctx.now, Exception.message(error))
      reraise error, __STACKTRACE__
  end
end
