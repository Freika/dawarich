defmodule Dawarich.Integrations.SyncScheduling do
  @moduledoc false

  alias Dawarich.{Entitlements, RailsCommands}
  alias Dawarich.AirTrail.ImportFlightsWorker
  alias Dawarich.Imports.{Teslamate, Trek}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias DawarichWeb.LayoutAssigns

  @namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F, 0xD4,
               0x30, 0xC8>>

  def backoff(%Oban.Job{attempt: attempt}) do
    count = attempt - 1
    Integer.pow(count, 4) + 15 + :rand.uniform(10 * (count + 1)) - 1
  end

  def key(:airtrail), do: "cron:airtrail_flight_import_job"
  def key(:teslamate), do: "cron:teslamate_sync_job"
  def key(:trek), do: "cron:trek_sync_job"
  def slot(%Oban.Job{inserted_at: at}), do: at |> DateTime.to_unix() |> div(60) |> Kernel.*(60)
  def event_id(kind, slot, id), do: uuid("integrations.#{kind}:#{slot}:#{id}")
  def receipt_id(kind, slot, id), do: uuid("integrations.#{kind}.scheduled:#{slot}:#{id}")

  defp uuid(name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha, @namespace <> name)
    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  def run(repo, oban, kind, slot, opts \\ []), do: sweep(repo, oban, kind, slot, opts, 0)

  defp sweep(repo, oban, kind, slot, opts, cursor) do
    case Ownership.with_owner(repo, key(kind), :oban, fn ->
           batch(repo, oban, kind, slot, opts, cursor)
         end) do
      {:ok, nil} -> :ok
      {:ok, next} -> sweep(repo, oban, kind, slot, opts, next)
      {:skip, _} -> {:cancel, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end

  defp batch(repo, oban, kind, slot, opts, cursor) do
    rows = repo.query!(query(kind), [cursor], log: false).rows

    owner = Ownership.lock(repo, command_key(kind))

    Enum.each(rows, fn [id, user_id] ->
      if allowed?(repo, kind, user_id, opts) and
           Processed.claim!(repo, receipt_id(kind, slot, id), key(kind)) do
        payload = %{"user_id" => user_id, "event_id" => event_id(kind, slot, id)}
        publish(repo, oban, kind, owner, id, payload)
        Keyword.get(opts, :hook, fn _ -> :ok end).(id)
      end
    end)

    if length(rows) == 1000, do: rows |> List.last() |> hd(), else: nil
  end

  defp query(:airtrail),
    do: users_query("settings->>'airtrail_url' <> '' AND settings->>'airtrail_api_key' <> ''")

  defp query(:teslamate), do: users_query("settings->>'teslamate_url' <> ''")

  defp query(:trek),
    do:
      "SELECT id, user_id FROM trip_sources WHERE id > $1 AND status = 0 AND provider = 'trek' ORDER BY id LIMIT 1000"

  defp users_query(predicate),
    do:
      "SELECT id, id FROM users WHERE deleted_at IS NULL AND id > $1 AND #{predicate} ORDER BY id LIMIT 1000"

  defp allowed?(repo, :trek, user_id, opts) do
    if LayoutAssigns.self_hosted?() do
      true
    else
      [[plan]] =
        repo.query!("SELECT plan FROM users WHERE id = $1 AND deleted_at IS NULL", [user_id],
          log: false
        ).rows

      Entitlements.full_access?(
        repo,
        %{id: user_id, plan: plan},
        false,
        Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      )
    end
  end

  defp allowed?(_repo, _kind, _user_id, _opts), do: true

  defp command_key(:airtrail), do: "command:imports.airtrail_flights"
  defp command_key(:teslamate), do: "command:imports.teslamate_sync"
  defp command_key(:trek), do: "command:imports.trek_sync"

  defp publish(_repo, oban, :airtrail, :oban, _id, payload),
    do: Oban.insert!(oban, ImportFlightsWorker.new(payload))

  defp publish(repo, _oban, :airtrail, :sidekiq, _id, payload),
    do: RailsCommands.insert!(repo, "integrations.airtrail_flights", payload)

  defp publish(_repo, oban, :teslamate, :oban, _id, payload),
    do:
      native_child(
        oban,
        Teslamate.SyncWorker,
        Map.take(payload, ["user_id"]),
        payload["event_id"]
      )

  defp publish(_repo, oban, :trek, :oban, id, payload),
    do:
      native_child(
        oban,
        Trek.SyncWorker,
        %{"source_id" => id, "after_id" => nil},
        payload["event_id"]
      )

  defp publish(repo, _oban, :teslamate, :sidekiq, _id, payload),
    do: RailsCommands.insert!(repo, "integrations.teslamate_sync", payload)

  defp publish(repo, _oban, :trek, :sidekiq, id, payload),
    do: RailsCommands.insert!(repo, "integrations.trek_sync", Map.put(payload, "source_id", id))

  defp native_child(oban, worker, payload, event_id) do
    {:ok, args} = worker.args_from_command(1, payload)
    Oban.insert!(oban, worker.new(Map.put(args, "event_id", event_id)))
  end
end
