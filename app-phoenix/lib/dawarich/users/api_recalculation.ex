defmodule Dawarich.Users.ApiRecalculation do
  @moduledoc false
  alias Dawarich.{RailsCache, Redis, RubyInteger}
  alias Dawarich.Settings.{Api, Progress}

  def create(repo, user, params, ctx) do
    with :ok <- Dawarich.Imports.Api.guard(user, ctx) do
      year =
        if Dawarich.Ingest.Ruby.blank?(params["year"]),
          do: nil,
          else: RubyInteger.to_i(params["year"])

      if year && (year < 2000 or year > ctx.now.year + 1) do
        error(400, "invalid_year")
      else
        enqueue(repo, user, year, ctx)
      end
    end
  rescue
    _ -> {:error, 500, Api.failure()}
  end

  defp enqueue(repo, user, year, ctx) do
    key = "recalculation_pending:#{user.id}"

    case repo.transaction(fn ->
           repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user.id], log: false)

           if pending?(key),
             do: repo.rollback(error(409, "recalculation_already_in_progress_for_this_user"))

           bytes =
             Dawarich.RailsCache.Wire.encode_boolean(true,
               expires_at: System.system_time(:second) + 1800
             )

           {:ok, "OK"} = Redis.cache_command(["SET", key, bytes, "EX", "1800"])

           payload = %{
             "user_id" => user.id,
             "year" => year,
             "notify" => true,
             "job_queue" => nil,
             "source_job_id" => Ecto.UUID.generate(),
             "ambient_zone" => Dawarich.UserTimeZone.iana(repo, Api.read(repo, user.id))
           }

           Progress.produce(repo, "users.recalculate_data", payload, user.id, ctx)
           :ok
         end) do
      {:ok, :ok} ->
        Map.get(ctx, :after_commit, fn -> :ok end).()

        {:ok, 202,
         %{"message" => t("recalculation_queued_tracks_stats_and_digests_will_be_regenerated_in")}}

      {:error, outcome} ->
        outcome
    end
  end

  defp pending?(key) do
    case RailsCache.get(key) do
      {:ok, value} -> value not in [false, nil]
      :miss -> false
      _ -> raise "recalculation pending storage unavailable"
    end
  end

  defp error(status, key), do: {:error, status, %{"error" => t(key)}}
  defp t(key), do: Dawarich.I18n.en!("controllers.api.v1.recalculations." <> key)
end
