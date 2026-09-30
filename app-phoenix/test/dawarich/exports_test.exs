defmodule Dawarich.ExportsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Exports

  setup do
    rows("TRUNCATE public.exports RESTART IDENTITY")
    :ok
  end

  defp user!(settings \\ %{}) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ($1, $2, now(), now()) RETURNING id",
        ["e#{System.unique_integer([:positive])}@example.test", settings]
      )

    id
  end

  defp export!(user_id, file_type \\ 0) do
    [[id]] =
      rows(
        """
        INSERT INTO exports (name, status, file_format, file_type, start_at, end_at, user_id, created_at, updated_at)
        VALUES ('wave2 export', 0, 0, $2, '2026-03-29 00:00:00.5', '2026-03-30 00:00:00', $1, now(), now())
        RETURNING id
        """,
        [user_id, file_type]
      )

    id
  end

  defp blob(key \\ "k" <> Dawarich.Storage.generate_key()) do
    %{
      key: key,
      filename: "wave2 export.zip",
      content_type: "application/zip",
      metadata: ~s({"identified":true,"analyzed":true}),
      service_name: "local",
      byte_size: 42,
      checksum: "c2hlY2tzdW0="
    }
  end

  defp status(id), do: rows("SELECT status FROM exports WHERE id = $1", [id])
  defp notifications, do: rows("SELECT kind, title, content FROM notifications ORDER BY id")
  defp uuid, do: Ecto.UUID.generate()

  defp claimed!(settings \\ %{}) do
    user_id = user!(settings)
    id = export!(user_id)
    event_id = uuid()
    {:run, export} = Exports.claim(ScratchRepo, id, user_id, event_id)
    {export, event_id}
  end

  test "claim: created → processing once with an export_claims row; another event :skip; the same event again {:run, _}" do
    user_id = user!(%{"locale" => "de"})
    id = export!(user_id)
    first = uuid()

    assert {:run, export} = Exports.claim(ScratchRepo, id, user_id, first)

    assert export == %{
             id: id,
             user_id: user_id,
             name: "wave2 export",
             file_format: 0,
             start_at: 1_774_742_400,
             end_at: 1_774_828_800,
             settings: %{"locale" => "de"}
           }

    assert [[1, %NaiveDateTime{}]] =
             rows("SELECT status, processing_started_at FROM exports WHERE id = $1", [id])

    assert rows("SELECT export_id, event_id FROM phoenix.export_claims") ==
             [[id, Ecto.UUID.dump!(first)]]

    assert Exports.claim(ScratchRepo, id, user_id, uuid()) == :skip
    assert {:run, ^export} = Exports.claim(ScratchRepo, id, user_id, first)
  end

  test "claim ignores user_data exports and another user's export" do
    user_id = user!()
    user_data = export!(user_id, 1)
    points = export!(user_id)

    assert Exports.claim(ScratchRepo, user_data, user_id, uuid()) == :skip
    assert Exports.claim(ScratchRepo, points, user!(), uuid()) == :skip
    assert status(user_data) == [[0]]
    assert status(points) == [[0]]
    assert rows("SELECT count(*) FROM phoenix.export_claims") == [[0]]
  end

  test "complete writes blob, attachment, status 2 and one info notification plus event atomically" do
    {export, event_id} = claimed!()
    now = ~N[2026-09-28 10:00:00.000000]
    blob = blob()

    assert_raise Postgrex.Error, fn ->
      Exports.complete(
        ScratchRepo,
        export,
        event_id,
        %{blob | filename: nil},
        %{title: "T", content: "C"},
        now
      )
    end

    assert status(export.id) == [[1]]
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert notifications() == []

    assert Exports.complete(ScratchRepo, export, event_id, blob, %{title: "T", content: "C"}, now) ==
             :ok

    assert [[blob_id | values]] =
             rows(
               "SELECT id, key, filename, content_type, metadata, service_name, byte_size, checksum, created_at FROM active_storage_blobs"
             )

    assert values == [
             blob.key,
             blob.filename,
             blob.content_type,
             blob.metadata,
             blob.service_name,
             blob.byte_size,
             blob.checksum,
             now
           ]

    assert rows(
             "SELECT name, record_type, record_id, blob_id, created_at FROM active_storage_attachments"
           ) == [["file", "Export", export.id, blob_id, now]]

    assert rows("SELECT status, error_message, updated_at FROM exports WHERE id = $1", [export.id]) ==
             [[2, nil, now]]

    assert notifications() == [[0, "T", "C"]]
    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[1]]
  end

  test "complete after Rails stale recovery set failed returns :lost and writes nothing" do
    {export, event_id} = claimed!()
    rows("UPDATE exports SET status = 3 WHERE id = $1", [export.id])

    assert Exports.complete(ScratchRepo, export, event_id, blob(), %{title: "T", content: "C"}) ==
             :lost

    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert rows("SELECT count(*) FROM active_storage_attachments") == [[0]]
    assert notifications() == []
    assert status(export.id) == [[3]]
  end

  test "complete by an event that is not the claimant returns :lost" do
    {export, _event_id} = claimed!()

    assert Exports.complete(ScratchRepo, export, uuid(), blob(), %{title: "T", content: "C"}) ==
             :lost

    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert notifications() == []
    assert status(export.id) == [[1]]
  end

  test "complete replaces an existing attachment row and keeps the old blob" do
    {export, event_id} = claimed!()

    [[old_blob]] =
      rows(
        "INSERT INTO active_storage_blobs (key, filename, service_name, byte_size, created_at) VALUES ('old', 'old.zip', 'local', 1, now()) RETURNING id"
      )

    rows(
      "INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at) VALUES ('file', 'Export', $1, $2, now())",
      [export.id, old_blob]
    )

    assert Exports.complete(ScratchRepo, export, event_id, blob("new"), %{
             title: "T",
             content: "C"
           }) ==
             :ok

    assert [[new_blob]] = rows("SELECT id FROM active_storage_blobs WHERE key = 'new'")

    assert rows("SELECT blob_id FROM active_storage_attachments WHERE record_id = $1", [export.id]) ==
             [[new_blob]]

    assert rows("SELECT key FROM active_storage_blobs ORDER BY id") == [["old"], ["new"]]
  end

  test "fail! stores a message cut to 1000 characters and one error notification; after completion it is a no-op" do
    {export, event_id} = claimed!()
    message = String.duplicate("x", 1500)

    assert Exports.fail!(ScratchRepo, export, event_id, message, %{title: "F", content: "boom"}) ==
             :ok

    assert rows("SELECT status, length(error_message) FROM exports WHERE id = $1", [export.id]) ==
             [[3, 1000]]

    assert notifications() == [[2, "F", "boom"]]

    {done, done_event} = claimed!()
    :ok = Exports.complete(ScratchRepo, done, done_event, blob(), %{title: "T", content: "C"})

    assert Exports.fail!(ScratchRepo, done, done_event, "late", %{title: "F", content: "late"}) ==
             :ok

    assert rows("SELECT status, error_message FROM exports WHERE id = $1", [done.id]) ==
             [[2, nil]]

    assert notifications() == [[2, "F", "boom"], [0, "T", "C"]]
  end

  test "notification texts follow the owner's locale" do
    {export, _} = claimed!(%{"locale" => "de"})
    {english, _} = claimed!()

    assert Exports.success_notification(english) == %{
             title: "Export finished",
             content: ~s(Export "wave2 export" successfully finished.)
           }

    assert Exports.failure_notification(english, RuntimeError.exception("boom")) == %{
             title: "Export failed",
             content: ~s(Export "wave2 export" failed: boom, stacktrace: )
           }

    assert Exports.success_notification(export).title == "Export beendet"
  end
end
