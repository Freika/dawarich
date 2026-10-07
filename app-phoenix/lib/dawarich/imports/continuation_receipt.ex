defmodule Dawarich.Imports.ContinuationReceipt do
  @moduledoc false
  alias Dawarich.Imports.{Fence, ImportState, LeaseLost}
  alias Dawarich.Jobs.Processed

  def admission(lease) do
    events =
      case lease.repo.query!(
             "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 FOR UPDATE",
             [lease.import.id],
             log: false
           ).rows do
        [[%{"kind" => "continuation", "events" => events}]] when is_map(events) -> events
        _ -> %{}
      end

    if receipt_predecessor?(lease, events) or pending_predecessor?(lease, events),
      do: :predecessor,
      else: :ok
  end

  defp receipt_predecessor?(lease, events) do
    Enum.any?(events, fn {event, receipt} ->
      event != lease.event_id and unfinished?(lease.repo, event, receipt) and
        receipt_position(lease, event, receipt) < position(lease)
    end)
  end

  defp receipt_position(lease, event, receipt) do
    job_id =
      receipt["job_id"] ||
        case lease.repo.query!(
               "SELECT id FROM oban.oban_jobs WHERE worker=$1 AND args @> $2 ORDER BY id LIMIT 1",
               [
                 lease.worker,
                 %{
                   "event_id" => event,
                   "import_id" => lease.import.id,
                   "user_id" => lease.import.user_id
                 }
               ],
               log: false
             ).rows do
          [[id]] -> id
          [] -> 0
        end

    {receipt["index"] || 0, job_id}
  end

  defp pending_predecessor?(lease, events) do
    lease.repo.query!(
      "SELECT id,args FROM oban.oban_jobs WHERE worker=$1 AND args @> $2",
      [lease.worker, %{"import_id" => lease.import.id, "user_id" => lease.import.user_id}],
      log: false
    ).rows
    |> Enum.any?(fn [id, args] ->
      with event when is_binary(event) and event != lease.event_id <- args["event_id"],
           {:ok, _} <- Ecto.UUID.cast(event),
           {:ok, payload} <- Dawarich.Imports.GoogleTakeoutResume.validate(args["continuation"]) do
        {payload["current_index"], id} < position(lease) and
          unfinished?(lease.repo, event, events[event] || %{})
      else
        _ -> false
      end
    end)
  end

  defp unfinished?(repo, event, receipt),
    do: receipt["complete"] != true and not Processed.done?(repo, event)

  defp position(lease), do: {lease.continuation["current_index"], lease.job_id}

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
            "index" => index,
            "job_id" => lease.job_id
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
