defmodule Dawarich.Imports.ImportState do
  @moduledoc false
  alias Dawarich.Imports.{Lease, LeaseLost}

  def with_snapshot(lease, fun) do
    guard = if lease.mode == :terminal, do: &Lease.terminal_effect!/2, else: &Lease.effect!/2
    state = guard.(lease, fn -> snapshot!(lease) end)
    Process.put(key(lease), state)

    try do
      fun.(state)
    after
      Process.delete(key(lease))
    end
  end

  def mode(lease), do: state!(lease).mode
  def with_blob(lease), do: effect!(lease, fn -> state!(lease).blob end)

  def effect!(lease, fun) do
    state = state!(lease)
    guard = if state.mode == :terminal, do: &Lease.terminal_effect!/2, else: &Lease.effect!/2

    guard.(lease, fn ->
      [[status, source]] =
        lease.repo.query!("SELECT status,source FROM imports WHERE id=$1", [lease.import.id],
          log: false
        ).rows

      unless status == state.status and source == state.import.source and
               attachment!(lease) == state.attachment,
             do: raise(LeaseLost)

      fun.()
    end)
  end

  def source!(lease, source) do
    effect!(lease, fn ->
      lease.repo.query!("UPDATE imports SET source=$2 WHERE id=$1", [lease.import.id, source],
        log: false
      )
    end)

    state = state!(lease)
    Process.put(key(lease), %{state | import: %{state.import | source: source}})
    :ok
  end

  def start!(lease, now) do
    effect!(lease, fn ->
      lease.repo.query!(
        "UPDATE imports SET additional_data_extraction_status=CASE WHEN additional_data_extraction_status=5 THEN 0 ELSE additional_data_extraction_status END,status=1,raw_points=0,doubles=0,processing_started_at=CASE WHEN status<>1 THEN $2 ELSE processing_started_at END,updated_at=$2 WHERE id=$1",
        [lease.import.id, naive(now)],
        log: false
      )
    end)

    change(lease, :processing, 1)
    :ok
  end

  def fail!(lease, error, now) do
    effect!(lease, fn ->
      lease.repo.query!(
        "UPDATE imports SET additional_data_extraction_status=CASE WHEN additional_data_extraction_status=5 THEN 0 ELSE additional_data_extraction_status END,status=3,error_message=$2,updated_at=$3 WHERE id=$1",
        [lease.import.id, Exception.message(error), naive(now)],
        log: false
      )
    end)

    change(lease, :failed, 3)
    :ok
  end

  def complete!(lease, now) do
    if state!(lease).status == 1 do
      effect!(lease, fn ->
        lease.repo.query!(
          "UPDATE imports SET additional_data_extraction_status=CASE WHEN additional_data_extraction_status=5 THEN 0 ELSE additional_data_extraction_status END,status=2,updated_at=$2 WHERE id=$1",
          [lease.import.id, naive(now)],
          log: false
        )

        lease.repo.query!(
          "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2 WHERE import_id=$1",
          [lease.import.id, %{"attachment" => state!(lease).attachment}],
          log: false
        )
      end)

      change(lease, :terminal, 2)
    else
      if lease.lane == "command:imports.process_normal" and state!(lease).status == 3,
        do: terminal_failed!(lease)
    end

    :ok
  end

  defp terminal_failed!(lease) do
    effect!(lease, fn ->
      lease.repo.query!(
        "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2 WHERE import_id=$1",
        [lease.import.id, %{"attachment" => state!(lease).attachment}],
        log: false
      )
    end)

    change(lease, :terminal, 3)
  end

  def import!(lease) do
    effect!(lease, fn -> import_row!(lease) end)
  end

  defp snapshot!(lease) do
    attachment = attachment!(lease)
    import = import_row!(lease)

    if lease.mode == :terminal do
      [[saved]] =
        lease.repo.query!(
          "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1",
          [lease.import.id],
          log: false
        ).rows

      unless saved == %{"attachment" => attachment}, do: raise(LeaseLost)
    end

    %{
      mode: lease.mode,
      status: import.status,
      attachment: attachment,
      import: import,
      blob: blob(attachment)
    }
  end

  defp import_row!(lease) do
    result =
      lease.repo.query!(
        "SELECT id,user_id,name,source,status,raw_points,doubles,raw_data,additional_data_extraction_status,additional_data_extraction FROM imports WHERE id=$1",
        [lease.import.id],
        log: false
      )

    [values] = result.rows

    [
      :id,
      :user_id,
      :name,
      :source,
      :status,
      :raw_points,
      :doubles,
      :raw_data,
      :additional_data_extraction_status,
      :additional_data_extraction
    ]
    |> Enum.zip(values)
    |> Map.new()
  end

  defp attachment!(lease) do
    case lease.repo.query!(
           "SELECT a.id,a.blob_id,b.key,b.filename,b.byte_size,b.checksum,b.service_name FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1 AND a.name='file' ORDER BY a.id FOR SHARE OF a,b",
           [lease.import.id],
           log: false
         ).rows do
      [] -> nil
      [row] -> row
      _ -> raise ArgumentError, "Import has multiple file attachments"
    end
  end

  defp blob(nil), do: nil

  defp blob([_, id, key, filename, size, checksum, service]),
    do: %{
      id: id,
      key: key,
      filename: filename,
      byte_size: size,
      checksum: checksum,
      service_name: service
    }

  defp state!(lease), do: Process.get(key(lease)) || raise(LeaseLost)
  defp key(lease), do: {__MODULE__, lease.scope}

  defp change(lease, mode, status),
    do: Process.put(key(lease), %{state!(lease) | mode: mode, status: status})

  defp naive(%DateTime{} = now), do: DateTime.to_naive(now)
end
