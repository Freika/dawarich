defmodule Dawarich.Imports.UploadsTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.Uploads
  alias Dawarich.Storage

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "native-upload-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
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

  test "native reservation and verified binary write produce an owner-bound attachment token",
       c do
    bytes = "<gpx><trk/></gpx>"

    attrs = %{
      "filename" => "route.gpx",
      "byte_size" => byte_size(bytes),
      "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
      "content_type" => "application/gpx+xml"
    }

    assert {:ok, blob} = Uploads.reserve(ScratchRepo, c.user, attrs, c.config)
    assert [[reserved_key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])

    assert {:error, :forbidden} =
             Uploads.fetch(ScratchRepo, %{c.user | id: c.user.id + 1}, blob.signed_id)

    assert {:error, :not_uploaded} = Uploads.fetch(ScratchRepo, c.user, blob.signed_id)
    file = Path.join(c.config.root, "input")
    File.write!(file, bytes)
    assert :ok = Uploads.write(ScratchRepo, c.user, blob.upload_token, file, c.config)
    assert {:ok, stored} = Uploads.fetch(ScratchRepo, c.user, blob.signed_id)
    assert File.read!(Storage.disk_path(c.config.root, stored.key)) == bytes
    assert stored.key == reserved_key
    assert stored.byte_size == byte_size(bytes)
    assert stored.service_name == "local"

    assert {:error, :invalid_token} =
             Uploads.fetch(ScratchRepo, c.user, blob.signed_id <> "tampered")
  end

  test "wrong checksum leaves a reservation unusable and does not write storage", c do
    attrs = %{
      "filename" => "route.gpx",
      "byte_size" => 3,
      "checksum" => Base.encode64(:crypto.hash(:md5, "abc")),
      "content_type" => "application/gpx+xml"
    }

    assert {:ok, blob} = Uploads.reserve(ScratchRepo, c.user, attrs, c.config)
    file = Path.join(c.config.root, "input")
    File.write!(file, "xyz")

    assert {:error, :integrity} =
             Uploads.write(ScratchRepo, c.user, blob.upload_token, file, c.config)

    assert {:error, :not_uploaded} = Uploads.fetch(ScratchRepo, c.user, blob.signed_id)
    assert [] == Path.wildcard(Path.join([c.config.root, "*", "*", "*"]))
  end

  test "trial limits and malformed protocol fields are enforced before reservation", c do
    valid = %{
      "filename" => "route.gpx",
      "byte_size" => 1,
      "checksum" => Base.encode64(:crypto.hash(:md5, "a")),
      "content_type" => "application/gpx+xml"
    }

    assert {:error, :invalid_blob} =
             Uploads.reserve(
               ScratchRepo,
               c.user,
               %{valid | "filename" => "../route.gpx"},
               c.config
             )

    assert {:error, :file_too_large} =
             Uploads.reserve(
               ScratchRepo,
               %{c.user | status: 2},
               %{valid | "byte_size" => 11 * 1024 * 1024 + 1},
               c.config
             )

    assert {:error, :inactive} =
             Uploads.reserve(ScratchRepo, %{c.user | active_until: nil}, valid, c.config)
  end
end
