defmodule Dawarich.Imports.DestroyEffects do
  @moduledoc false
  alias Dawarich.Imports.{DestroyLease, Events}
  alias Dawarich.RailsCommands

  def status!(lease) do
    DestroyLease.effect!(lease, fn ->
      insert!(lease, "imports.destroy_status", %{})
      Events.broadcast(lease.user)
    end)
  end

  def callback!(lease, step, payload),
    do: insert!(lease, "imports.destroy_callbacks", Map.put(payload, "step", step))

  def insert!(lease, kind, payload) do
    RailsCommands.insert!(
      lease.repo,
      kind,
      Map.merge(
        %{
          "import_id" => lease.id,
          "user_id" => lease.user,
          "event_id" => lease.job.args["event_id"]
        },
        payload
      )
    )
  end

  def points!(lease, timestamps) do
    stamps =
      Enum.uniq_by(timestamps, fn at ->
        DateTime.from_unix!(at || 0).year |> max(1970) |> min(2100)
      end)

    Dawarich.RailsEffects.tile_epoch(lease.repo, lease.user, stamps)
  end

  def visits!(lease, rows) do
    active = Enum.reject(rows, fn [_id, _place, _time, demo] -> demo end)

    times =
      Enum.map(active, fn [_id, _place, time, _demo] ->
        DateTime.from_naive!(time, "Etc/UTC") |> DateTime.to_iso8601()
      end)

    places =
      Enum.map(active, fn [_id, place, _time, _demo] -> place end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if times != [],
      do:
        RailsCommands.insert!(lease.repo, "visit_months_changed", %{
          "user_id" => lease.user,
          "started_at" => times
        })

    if places != [], do: callback!(lease, "places_cleanup", %{"place_ids" => places})
  end

  def finish!(lease) do
    DestroyLease.effect!(lease, fn ->
      insert!(lease, "imports.destroy_stats", %{})
      insert!(lease, "imports.destroy_complete", %{})
      Dawarich.Jobs.Processed.mark!(lease.repo, lease.job.args["event_id"], "imports.destroy")
      Events.broadcast(lease.user)
    end)
  end
end
