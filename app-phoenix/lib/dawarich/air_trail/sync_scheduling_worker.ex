defmodule Dawarich.AirTrail.SyncSchedulingWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 3

  alias Dawarich.AirTrail.ImportFlightsWorker
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.RailsCommands

  @key "cron:airtrail_flight_import_job"
  @leaf "command:imports.airtrail_flights"
  @namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F, 0xD4,
               0x30, 0xC8>>

  def key, do: @key
  def slot(%Oban.Job{inserted_at: at}), do: at |> DateTime.to_unix() |> div(60) |> Kernel.*(60)

  def event_id(slot, user_id), do: uuid("integrations.airtrail:#{slot}:#{user_id}")
  def receipt_id(slot, user_id), do: uuid("integrations.airtrail.scheduled:#{slot}:#{user_id}")

  defp uuid(name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha, @namespace <> name)

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job), do: run(Dawarich.Jobs.repo(), conf.name, slot(job))

  def run(repo, oban, slot, opts \\ []), do: sweep(repo, oban, slot, opts, 0)

  defp sweep(repo, oban, slot, opts, cursor) do
    case Ownership.with_owner(repo, @key, :oban, fn -> batch(repo, oban, slot, opts, cursor) end) do
      {:ok, nil} -> :ok
      {:ok, next} -> sweep(repo, oban, slot, opts, next)
      {:skip, _} -> {:cancel, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end

  defp batch(repo, oban, slot, opts, cursor) do
    rows =
      repo.query!(
        "SELECT id FROM users WHERE deleted_at IS NULL AND id > $1 " <>
          "AND settings->>'airtrail_url' <> '' AND settings->>'airtrail_api_key' <> '' " <>
          "ORDER BY id LIMIT 1000",
        [cursor],
        log: false
      ).rows

    owner = Ownership.lock(repo, @leaf)

    Enum.each(rows, fn [user_id] ->
      event_id = event_id(slot, user_id)

      if Processed.claim!(repo, receipt_id(slot, user_id), @key) do
        payload = %{"user_id" => user_id, "event_id" => event_id}

        case owner do
          :oban -> Oban.insert!(oban, ImportFlightsWorker.new(payload))
          :sidekiq -> RailsCommands.insert!(repo, "integrations.airtrail_flights", payload)
        end

        Keyword.get(opts, :hook, fn _ -> :ok end).(user_id)
      end
    end)

    if length(rows) == 1000, do: rows |> List.last() |> hd(), else: nil
  end
end
