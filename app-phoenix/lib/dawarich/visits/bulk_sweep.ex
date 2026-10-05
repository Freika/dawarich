defmodule Dawarich.Visits.BulkSweep do
  @moduledoc false

  alias Dawarich.{Entitlements, RailsCommands, UserTimeZone}
  alias Dawarich.Geocoding.Config
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Visits.{BulkSweepWorker, Calendar, Settings, SuggestWorker}

  @namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F, 0xD4,
               0x30, 0xC8>>
  @users """
  SELECT id, settings, plan FROM users WHERE deleted_at IS NULL AND status = 1 AND points_count > 0
    AND id > $1 AND (cardinality($2::bigint[]) = 0 OR id = ANY($2::bigint[])) ORDER BY id LIMIT 1000
  """

  def cron_id(slot), do: uuid(@namespace, "visits.bulk:cron:#{slot}")
  def child_id(root, user, index), do: uuid(Ecto.UUID.dump!(root), "suggest:#{user}:#{index}")
  def receipt_id(root, user), do: uuid(Ecto.UUID.dump!(root), "scheduled:#{user}")

  def run(repo, oban, args, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    if Config.resolve(repo, env).enabled do
      work = fn -> batch(repo, oban, args, opts, env) end

      result =
        if args["cron"],
          do: Ownership.with_owner(repo, BulkSweepWorker.key(), :oban, work),
          else: repo.transaction(work)

      case result do
        {:ok, :ok} -> :ok
        {:skip, _} -> {:cancel, :not_owner}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp batch(repo, oban, args, opts, env) do
    unless Processed.done?(repo, args["event_id"]) do
      rows = repo.query!(@users, [args["after_id"] || 0, args["user_ids"]], log: false).rows
      owner = Ownership.lock(repo, "command:visits.suggest")
      chunks = Calendar.time_chunks(args["start_at"], args["end_at"])

      for [id, settings, plan] <- rows,
          Settings.policy(settings).suggestions_enabled,
          Processed.claim!(repo, receipt_id(args["event_id"], id), "visits.bulk_suggest") do
        zone_env = Map.put_new(env, "TIME_ZONE", "UTC")
        [[zone]] = UserTimeZone.query!("SELECT name FROM z", [], settings, repo, zone_env).rows
        hosted = DawarichWeb.LayoutAssigns.self_hosted?(env)
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        restricted = not Entitlements.full_access?(repo, %{id: id, plan: plan}, hosted, now)

        for {{start, stop}, index} <- Enum.with_index(chunks) do
          payload = %{
            "user_id" => id,
            "start_at" => start,
            "end_at" => stop,
            "stepping" => "fixed",
            "time_zone" => zone,
            "plan_restricted" => restricted
          }

          event = child_id(args["event_id"], id, index)
          publish(repo, oban, payload, event, owner)
        end

        Keyword.get(opts, :hook, fn _ -> :ok end).(id)
      end

      if length(rows) == 1000 do
        next = Map.put(args, "after_id", rows |> List.last() |> hd())
        Oban.insert!(oban, BulkSweepWorker.new(next))
      else
        Processed.mark!(repo, args["event_id"], "visits.bulk_suggest")
      end
    end

    :ok
  end

  defp publish(_repo, oban, payload, event, :oban) do
    {:ok, decoded} = SuggestWorker.args_from_command(1, payload)
    Oban.insert!(oban, SuggestWorker.new(Map.put(decoded, "event_id", event)))
  end

  defp publish(repo, _oban, payload, event, :sidekiq),
    do: RailsCommands.insert!(repo, "visits.suggest", Map.put(payload, "event_id", event))

  defp uuid(namespace, name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha, namespace <> name)
    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
