defmodule Dawarich.Imports.UploadsTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.Uploads

  setup do
    root = Path.join(System.tmp_dir!(), "rails-upload-" <> Ecto.UUID.generate())
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "a Rails-signed blob id resolves to its blob with decoded metadata", c do
    blob =
      Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "route.gpx", "<gpx/>",
        metadata: %{"dawarich_client_wrapped" => false}
      )

    assert {:ok, stored} = Uploads.fetch(ScratchRepo, blob.signed_id)
    assert stored.id == blob.id
    assert stored.filename == "route.gpx"
    assert stored.metadata == %{"dawarich_client_wrapped" => false}
  end

  test "tampered, foreign-purpose and missing references are refused", c do
    blob = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "route.gpx", "<gpx/>")

    assert {:error, :invalid_token} = Uploads.fetch(ScratchRepo, blob.signed_id <> "tampered")
    assert {:error, :invalid_token} = Uploads.fetch(ScratchRepo, "route.gpx")
    assert {:error, :invalid_token} = Uploads.fetch(ScratchRepo, nil)

    assert {:error, :not_found} =
             Uploads.fetch(ScratchRepo, Dawarich.RailsMessages.blob_id(blob.id + 1_000_000))
  end
end
