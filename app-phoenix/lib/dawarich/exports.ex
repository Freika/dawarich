defmodule Dawarich.Exports do
  @moduledoc false

  alias Dawarich.Mail.ExploreFeatures

  @claim """
  WITH claimed AS (
    UPDATE exports SET status = 1, processing_started_at = $4, updated_at = $4
    WHERE id = $1 AND user_id = $2 AND status = 0 AND file_type = 0
    RETURNING id
  )
  INSERT INTO phoenix.export_claims (export_id, event_id, claimed_at)
  SELECT id, $3::uuid, now() FROM claimed
  ON CONFLICT (export_id) DO UPDATE SET event_id = EXCLUDED.event_id, claimed_at = EXCLUDED.claimed_at
  RETURNING export_id
  """

  @mine """
  SELECT 1 FROM exports e JOIN phoenix.export_claims c ON c.export_id = e.id
  WHERE e.id = $1 AND e.status = 1 AND c.event_id = $2
  """

  @complete """
  UPDATE exports SET status = 2, error_message = NULL, updated_at = $2
  WHERE id = $1 AND status = 1
    AND EXISTS (SELECT 1 FROM phoenix.export_claims WHERE export_id = $1 AND event_id = $3)
  RETURNING id
  """

  @fail """
  UPDATE exports SET status = 3, error_message = $2, updated_at = $3
  WHERE id = $1 AND status = 1
    AND EXISTS (SELECT 1 FROM phoenix.export_claims WHERE export_id = $1 AND event_id = $4)
  RETURNING id
  """

  @insert_blob """
  INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, checksum, created_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id
  """

  @drop_attachment "DELETE FROM active_storage_attachments WHERE record_type = 'Export' AND record_id = $1 AND name = 'file'"

  @attach """
  INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
  VALUES ('file', 'Export', $1, $2, $3)
  """

  @load """
  SELECT e.id, e.user_id, e.name, e.file_format,
         coalesce(floor(extract(epoch from e.start_at))::bigint, 0),
         coalesce(floor(extract(epoch from e.end_at))::bigint, 0),
         u.settings
  FROM exports e JOIN users u ON u.id = e.user_id
  WHERE e.id = $1
  """

  def claim(repo, export_id, user_id, event_id, now \\ NaiveDateTime.utc_now()) do
    uuid = Ecto.UUID.dump!(event_id)

    cond do
      repo.query!(@claim, [export_id, user_id, uuid, now], log: false).rows != [] ->
        {:run, load!(repo, export_id)}

      repo.query!(@mine, [export_id, uuid], log: false).rows != [] ->
        {:run, load!(repo, export_id)}

      true ->
        :skip
    end
  end

  def complete(repo, export, event_id, blob, notification, now \\ NaiveDateTime.utc_now()) do
    result =
      repo.transaction(fn ->
        case repo.query!(@complete, [export.id, now, Ecto.UUID.dump!(event_id)], log: false).rows do
          [] ->
            repo.rollback(:lost)

          [[_]] ->
            [[blob_id]] =
              repo.query!(
                @insert_blob,
                [
                  blob.key,
                  blob.filename,
                  blob.content_type,
                  blob.metadata,
                  blob.service_name,
                  blob.byte_size,
                  blob.checksum,
                  now
                ],
                log: false
              ).rows

            repo.query!(@drop_attachment, [export.id], log: false)
            repo.query!(@attach, [export.id, blob_id, now], log: false)

            Dawarich.Notifications.create!(
              repo,
              export.user_id,
              :info,
              notification.title,
              notification.content,
              now
            )
        end
      end)

    case result do
      {:ok, _} -> :ok
      {:error, :lost} -> :lost
    end
  end

  def fail!(repo, export, event_id, message, notification, now \\ NaiveDateTime.utc_now()) do
    repo.transaction(fn ->
      params = [export.id, String.slice(message, 0, 1000), now, Ecto.UUID.dump!(event_id)]

      case repo.query!(@fail, params, log: false).rows do
        [] ->
          :lost

        [[_]] ->
          Dawarich.Notifications.create!(
            repo,
            export.user_id,
            :error,
            notification.title,
            notification.content,
            now
          )
      end
    end)

    :ok
  end

  def success_notification(export) do
    %{
      title: t(export, "export_finished"),
      content: t(export, "export_name_successfully_finished", %{"name" => export.name})
    }
  end

  def failure_notification(export, error) do
    %{
      title: t(export, "export_failed"),
      content:
        t(export, "export_name_failed_message_stacktrace_n", %{
          "name" => export.name,
          "message" => Exception.message(error),
          "backtrace" => ""
        })
    }
  end

  def t(export, key, bindings \\ %{}) do
    locale = ExploreFeatures.locale(export.settings, nil)
    {:ok, text} = Dawarich.I18n.t(locale, "services.exports.create." <> key, bindings)
    text
  end

  defp load!(repo, export_id) do
    [[id, user_id, name, file_format, start_at, end_at, settings]] =
      repo.query!(@load, [export_id], log: false).rows

    %{
      id: id,
      user_id: user_id,
      name: name,
      file_format: file_format,
      start_at: start_at,
      end_at: end_at,
      settings: settings
    }
  end
end
