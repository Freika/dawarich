defmodule Dawarich.Imports.UploadCreateTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.UploadCreate
  alias Dawarich.Jobs.Ownership

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "native-create-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)

    rows(
      "UPDATE users SET active_until=now()+interval '1 day',status=0,subscription_source=0,settings=$2 WHERE id=$1",
      [c.import.user_id, %{"timezone" => "Berlin", "locale" => "fr"}]
    )

    on_exit(fn -> File.rm_rf!(root) end)

    %{
      user: %{
        id: c.import.user_id,
        status: 0,
        subscription_source: 0,
        active_until: DateTime.add(DateTime.utc_now(), 86400),
        points_count: 0
      },
      config: %{service: "local", root: root}
    }
  end

  defp uploaded(c, name, bytes),
    do: Dawarich.RailsBlobFixture.create!(ScratchRepo, c.config.root, name, bytes)

  test "unknown plaintext GPX source is classified and native enqueue captures current Rails zone",
       c do
    blob = uploaded(c, "upload.gpx", "<?xml version=\"1.0\"?><gpx><trk/></gpx>")

    assert {:ok, [id]} =
             UploadCreate.create(ScratchRepo, c.user, [blob.signed_id], %{
               storage: c.config,
               self_hosted?: true
             })

    assert [[4, 0, "upload.gpx", 0]] =
             rows(
               "SELECT source,status,name,additional_data_extraction_status FROM imports WHERE id=$1",
               [id]
             )

    assert [[payload]] = rows("SELECT payload FROM job_outbox WHERE aggregate_id=$1", [id])
    assert payload == %{"import_id" => id, "user_id" => c.user.id, "time_zone" => "Berlin"}

    assert {:error, :already_attached} =
             UploadCreate.create(ScratchRepo, c.user, [blob.signed_id], %{
               storage: c.config,
               self_hosted?: true
             })
  end

  test "real client single-entry ZIP is retained at rest while classified for the native worker",
       c do
    name = "client.gpx"

    {:ok, {_, zip}} =
      :zip.create(~c"client.zip", [{String.to_charlist(name), "<gpx><trk/></gpx>"}], [:memory])

    blob = uploaded(c, name <> ".zip", zip)

    descriptor =
      Jason.encode!(%{
        "signed_id" => blob.signed_id,
        "client_wrapped" => true,
        "original_filename" => name
      })

    assert {:ok, [id]} =
             UploadCreate.create(ScratchRepo, c.user, [descriptor], %{
               storage: c.config,
               self_hosted?: true
             })

    assert [[4, ^name]] = rows("SELECT source,name FROM imports WHERE id=$1", [id])

    assert [[metadata]] =
             rows(
               "SELECT b.metadata FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_id=$1 AND a.record_type='Import'",
               [id]
             )

    assert Jason.decode!(metadata)["dawarich_original_filename"] == name
    assert [[1]] = rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id])
  end

  test "a non-GPX file refuses the whole batch before any write; Sidekiq-owned GPX continues on Rails",
       c do
    other = uploaded(c, "other.json", "{}")
    gpx = uploaded(c, "first.gpx", "<gpx><trk/></gpx>")
    context = %{storage: c.config, self_hosted?: true}
    [[last]] = rows("SELECT max(id) FROM imports")

    assert {:error, :rails_format} =
             UploadCreate.create(ScratchRepo, c.user, [gpx.signed_id, other.signed_id], context)

    assert [] == rows("SELECT id FROM imports WHERE id > $1", [last])
    assert [] == rows("SELECT id FROM active_storage_attachments")
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
    assert [] == rows("SELECT event_id FROM job_outbox")

    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    assert {:ok, [id]} = UploadCreate.create(ScratchRepo, c.user, [gpx.signed_id], context)

    assert [["imports.upload_created", %{"import_id" => ^id}]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")
  end

  test "forged tokens and exhausted trial quota create no import or enqueue", c do
    blob = uploaded(c, "third.gpx", "<gpx/>")

    assert {:error, :invalid_token} =
             UploadCreate.create(ScratchRepo, c.user, [blob.signed_id <> "x"], %{
               storage: c.config,
               self_hosted?: true
             })

    rows("UPDATE users SET status=2,subscription_source=0 WHERE id=$1", [c.user.id])

    for n <- 1..4,
        do:
          rows(
            "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES($1,$2,now(),now())",
            [c.user.id, "existing#{n}"]
          )

    assert {:error, :import_limit} =
             UploadCreate.create(ScratchRepo, c.user, [blob.signed_id], %{
               storage: c.config,
               self_hosted?: true
             })

    assert [] == rows("SELECT event_id FROM job_outbox")
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
  end

  test "same-second duplicate upload names roll back the whole batch", c do
    blobs = for _ <- 1..3, do: uploaded(c, "duplicate.gpx", "<gpx/>")

    assert {:error, :duplicate_name} =
             UploadCreate.create(ScratchRepo, c.user, Enum.map(blobs, & &1.signed_id), %{
               storage: c.config,
               self_hosted?: true
             })

    assert [[1]] = rows("SELECT count(*) FROM imports WHERE user_id=$1", [c.user.id])
    assert [] == rows("SELECT id FROM active_storage_attachments")
    assert [] == rows("SELECT event_id FROM job_outbox")
  end

  test "blob classification only needs its explicit historical service catalog", c do
    blob = uploaded(c, "catalog.gpx", "<gpx/>")

    assert {:ok, [id]} =
             UploadCreate.create(ScratchRepo, c.user, [blob.signed_id], %{
               services: %{"local" => c.config},
               self_hosted?: true
             })

    assert [[4]] = rows("SELECT source FROM imports WHERE id=$1", [id])
  end
end
