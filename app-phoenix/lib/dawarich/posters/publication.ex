defmodule Dawarich.Posters.Publication do
  @moduledoc false
  alias Dawarich.Jobs.Processed
  alias Dawarich.Posters.Command
  @owner "command:posters.create"

  def prepare(repo, id, user_id, event, holder, locale) do
    ctx = %{id: id, user_id: user_id, event_id: event, holder: holder, locale: locale}

    transaction(repo, fn ->
      lease!(repo, ctx)
      if Command.owner(repo) != :oban, do: repo.rollback(:lost)
      row = row!(repo, ctx)

      cond do
        Processed.done?(repo, event) ->
          :skip

        row.status == 2 ->
          Processed.mark!(repo, event, @owner)
          :skip

        true ->
          ctx =
            Map.merge(ctx, Map.take(row, [:name, :settings]))
            |> Map.put(:owner_stamp, stamp(repo))

          repo.query!("UPDATE posters SET status=1,updated_at=now() WHERE id=$1 AND user_id=$2", [
            id,
            user_id
          ])

          notify(repo, ctx)
          ctx
      end
    end)
  end

  def progress(repo, ctx, phase) do
    transaction(repo, fn ->
      current = fenced!(repo, ctx)

      if current.status == 2 or Processed.done?(repo, ctx.event_id) or
           current.settings["progress_phase"] == phase do
        :skip
      else
        settings = Map.put(current.settings, "progress_phase", phase)

        repo.query!("UPDATE posters SET settings=$2,updated_at=now() WHERE id=$1", [
          ctx.id,
          settings
        ])

        notify(repo, ctx)
        :updated
      end
    end)
  end

  def publish(repo, ctx, blobs), do: publish(repo, ctx, fn -> blobs end, fn _ -> :ok end)

  def publish(repo, ctx, upload, discard) do
    transaction(repo, fn ->
      current = fenced!(repo, ctx)

      if current.status == 2 or Processed.done?(repo, ctx.event_id) do
        :duplicate
      else
        blobs = upload.()

        try do
          [png, pdf] = blobs
          attach(repo, ctx, "image", png)
          attach(repo, ctx, "print_pdf", pdf)
          repo.query!("UPDATE posters SET status=2,updated_at=now() WHERE id=$1", [ctx.id])
          notify(repo, ctx)
          Processed.mark!(repo, ctx.event_id, @owner)
          :published
        rescue
          error ->
            discard.(blobs)
            reraise error, __STACKTRACE__
        end
      end
    end)
  end

  def fail(repo, ctx, message) do
    transaction(repo, fn ->
      current = fenced!(repo, ctx)

      if current.status == 2 or Processed.done?(repo, ctx.event_id) do
        :skip
      else
        repo.query!("UPDATE posters SET status=3,settings=$2,updated_at=now() WHERE id=$1", [
          ctx.id,
          Map.put(current.settings, "error", message)
        ])

        notify(repo, ctx)
        Processed.mark!(repo, ctx.event_id, @owner)
        :failed
      end
    end)
  end

  defp fenced!(repo, ctx) do
    lease!(repo, ctx)

    if Command.owner(repo) != :oban or stamp(repo) != ctx.owner_stamp,
      do: repo.rollback(:lost)

    row!(repo, ctx)
  end

  defp lease!(repo, ctx) do
    case repo.query!(
           "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
           ["posters:#{ctx.id}"]
         ).rows do
      [[holder, true]] when holder == ctx.holder -> :ok
      _ -> repo.rollback(:lost)
    end
  end

  defp row!(repo, ctx) do
    case repo.query!(
           "SELECT name,status,settings FROM posters WHERE id=$1 AND user_id=$2 FOR UPDATE",
           [ctx.id, ctx.user_id]
         ).rows do
      [[name, status, settings]] -> %{name: name, status: status, settings: settings}
      [] -> repo.rollback(:lost)
    end
  end

  defp stamp(repo),
    do:
      repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [@owner]).rows
      |> hd()
      |> hd()

  defp attach(repo, ctx, name, blob) do
    [[id]] =
      repo.query!(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()) RETURNING id",
        [
          blob.key,
          blob.filename,
          blob.content_type,
          blob.metadata,
          blob.service_name,
          blob.byte_size,
          blob.checksum
        ]
      ).rows

    repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES($1,'Poster',$2,$3,now())",
      [name, ctx.id, id]
    )
  end

  defp notify(repo, ctx),
    do:
      Command.progress(repo, %{
        "poster_id" => ctx.id,
        "user_id" => ctx.user_id,
        "locale" => ctx.locale
      })

  defp transaction(repo, fun) do
    repo.transaction(fun)
  rescue
    error -> {:error, error}
  end
end
