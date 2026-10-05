defmodule Dawarich.Achievements.BulkCheck do
  @moduledoc false
  alias Dawarich.Achievements.{Checker, CheckWorker}
  alias Dawarich.Jobs.{Ownership, Processed}

  @namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F, 0xD4,
               0x30, 0xC8>>
  @key "cron:achievements_bulk_check_job"

  def cron_id(slot), do: uuid(@namespace, "achievements.bulk:cron:#{slot}")
  def child_id(root, user), do: uuid(Ecto.UUID.dump!(root), "check:#{user}")
  def receipt_id(root, user), do: uuid(Ecto.UUID.dump!(root), "scheduled:#{user}")

  def run(repo, oban, args, opts \\ []) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      ids = eligible(repo, args["stale_only"])
      batches = Enum.chunk_every(ids, 200)
      batches = if batches == [], do: [[]], else: batches
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

      Enum.reduce_while(Enum.with_index(batches), :ok, fn {batch, index}, _ ->
        work = fn ->
          owner = Ownership.lock(repo, "command:achievements.check")

          unless Processed.done?(repo, args["event_id"]) do
            Enum.each(batch, fn id ->
              if Processed.claim!(
                   repo,
                   receipt_id(args["event_id"], id),
                   "achievements.bulk_check"
                 ) do
                publish(repo, oban, args, id, owner, DateTime.add(now, index * 300))
                Keyword.get(opts, :hook, fn _ -> :ok end).(id)
              end
            end)

            if index == length(batches) - 1,
              do: Processed.mark!(repo, args["event_id"], "achievements.bulk_check")
          end

          :ok
        end

        result =
          if opts[:cron],
            do: Ownership.with_owner(repo, @key, :oban, work),
            else: repo.transaction(work)

        case result do
          {:ok, :ok} -> {:cont, :ok}
          {:skip, _} -> {:halt, {:cancel, :not_owner}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp eligible(repo, stale) do
    repo.query!(
      """
      SELECT u.id FROM users u WHERE u.deleted_at IS NULL AND u.status IN (1,2)
      AND u.id IN (SELECT user_id FROM points WHERE (anomaly=false OR anomaly IS NULL) AND lonlat IS NOT NULL)
      AND (NOT $1 OR u.id NOT IN (SELECT user_id FROM achievement_progresses
        WHERE achievement_key='exploration' AND COALESCE((state->>'calculation_version')::integer,0)>=$2))
      """,
      [stale, Checker.calculation_version()],
      log: false
    ).rows
    |> List.flatten()
  end

  defp publish(_repo, oban, args, id, :oban, at) do
    payload = %{
      "user_id" => id,
      "notify" => args["notify"],
      "oldest_timestamp" => nil,
      "event_id" => child_id(args["event_id"], id)
    }

    Oban.insert!(oban, CheckWorker.new(payload, scheduled_at: at))
  end

  defp publish(repo, _oban, args, id, :sidekiq, at) do
    Dawarich.RailsCommands.insert!(repo, "achievements.bulk_check_leaf", %{
      "user_id" => id,
      "notify" => args["notify"],
      "event_id" => child_id(args["event_id"], id),
      "run_at" => DateTime.to_iso8601(at)
    })
  end

  defp uuid(namespace, name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha, namespace <> name)
    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
