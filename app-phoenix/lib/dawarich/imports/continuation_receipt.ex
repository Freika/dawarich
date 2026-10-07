defmodule Dawarich.Imports.ContinuationReceipt do
  @moduledoc false
  alias Dawarich.Imports.{Fence, ImportState, LeaseLost}
  alias Dawarich.Jobs.Processed

  def admission(lease) do
    case lease.repo.query!(
           "SELECT r.attachment_snapshot,i.processed FROM phoenix.import_runs r JOIN imports i ON i.id=r.import_id WHERE r.import_id=$1 FOR UPDATE OF r,i",
           [lease.import.id],
           log: false
         ).rows do
      [[%{"kind" => "continuation", "events" => events}, processed]] when is_map(events) ->
        cond do
          Map.has_key?(events, lease.event_id) ->
            :ok

          Enum.any?(events, fn {event, receipt} ->
            receipt["complete"] != true and not Processed.done?(lease.repo, event)
          end) ->
            :predecessor

          lease.continuation["current_index"] <
              Enum.reduce(events, processed || 0, fn {_event, receipt}, index ->
                max(index, receipt["index"] || 0)
              end) ->
            :stale_continuation

          true ->
            :ok
        end

      _ ->
        :ok
    end
  end

  def driver(lease, state, context, digest, index) do
    cursor =
      ImportState.effect!(lease, fn ->
        saved = load!(lease)

        identity = %{
          "attachment" => state.attachment,
          "source" => state.import.source,
          "digest" => digest
        }

        saved =
          case saved do
            nil -> %{"kind" => "continuation", "events" => %{}}
            %{"kind" => "continuation", "events" => events} when is_map(events) -> saved
            _ -> raise LeaseLost
          end

        receipt = saved["events"][lease.event_id]

        cursor =
          case receipt do
            nil ->
              0

            %{"cursor" => cursor, "identity" => ^identity}
            when is_integer(cursor) and cursor >= 0 ->
              cursor

            _ ->
              raise LeaseLost
          end

        receipt =
          Map.merge(receipt || %{}, %{
            "identity" => identity,
            "cursor" => cursor,
            "index" => index
          })

        save!(
          lease,
          saved |> put_in(["events", lease.event_id], receipt) |> Map.put("cursor", cursor)
        )

        cursor
      end)

    Map.merge(context, %{
      resume_lease: lease,
      resume_offset: cursor,
      continuation_progress?: true
    })
  end

  def complete(%{resume_lease: lease} = context, size) do
    Fence.run(context, fn ->
      saved = load!(lease)
      unless get_in(saved, ["events", lease.event_id, "cursor"]) == size, do: raise(LeaseLost)
      save!(lease, put_in(saved, ["events", lease.event_id, "complete"], true))
      :ok
    end)
  end

  def batch(%{resume_lease: lease} = context, offset, size, fun) do
    value =
      Fence.run(context, fn ->
        saved = load!(lease)
        unless get_in(saved, ["events", lease.event_id, "cursor"]) == offset, do: raise(LeaseLost)
        value = fun.()

        save!(
          lease,
          saved
          |> put_in(["events", lease.event_id, "cursor"], offset + size)
          |> Map.put("cursor", offset + size)
        )

        value
      end)

    if callback = context[:on_batch], do: callback.(offset + size)
    value
  end

  defp load!(lease) do
    [[saved]] =
      lease.repo.query!(
        "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 FOR UPDATE",
        [lease.import.id],
        log: false
      ).rows

    saved
  end

  defp save!(lease, saved) do
    lease.repo.query!(
      "UPDATE phoenix.import_runs SET attachment_snapshot=$2,updated_at=now() WHERE import_id=$1",
      [lease.import.id, saved],
      log: false
    )
  end
end
