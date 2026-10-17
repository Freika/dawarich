defmodule Dawarich.Imports.ImportsDestroyAchievementsEffects do
  @moduledoc false
  alias Dawarich.Imports.Postprocessing.Native

  def enqueue!(repo, user, oldest, event, now \\ DateTime.utc_now()) do
    repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended('import-achievements:' || $1::bigint::text,0))",
      [user],
      log: false
    )

    case repo.query!(
           "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker' AND state IN('available','scheduled','retryable') AND args->>'user_id'=$1 ORDER BY id LIMIT 1 FOR UPDATE",
           [to_string(user)],
           log: false
         ).rows do
      [[id, args]] ->
        value =
          [oldest, args["oldest_timestamp"]] |> Enum.reject(&is_nil/1) |> Enum.min(fn -> nil end)

        repo.query!(
          "UPDATE oban.oban_jobs SET args=$2 WHERE id=$1",
          [id, Map.put(args, "oldest_timestamp", value)],
          log: false
        )

      [] ->
        Native.publish!(
          repo,
          Dawarich.Achievements.CheckWorker,
          %{"user_id" => user, "notify" => true, "oldest_timestamp" => oldest},
          event,
          DateTime.add(now, 60)
        )
    end

    :ok
  end
end
