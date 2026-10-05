defmodule Dawarich.Test.ImportsExportsSeeds do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  def user!(id, settings),
    do: RailsUser.insert!(%{id: id, email: "a7-#{id}@dawarich.test", settings: settings})

  def import!(attrs) do
    stamp = NaiveDateTime.utc_now()

    row =
      Map.merge(
        %{
          name: "import #{attrs.id}",
          source: 4,
          status: 2,
          processed: 10,
          doubles: 0,
          demo: false,
          error_message: nil,
          additional_data_extraction_status: 0,
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )

    Dawarich.Test.SeedIds.insert_all!(Repo, "imports", [row])
    row
  end

  def export!(attrs) do
    stamp = NaiveDateTime.utc_now()

    row =
      Map.merge(
        %{
          name: "export #{attrs.id}",
          status: 2,
          file_format: 0,
          file_type: 0,
          url: nil,
          error_message: nil,
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )

    Dawarich.Test.SeedIds.insert_all!(Repo, "exports", [row])
    row
  end

  def file!(record_type, record_id, name, blob_id, byte_size, filename) do
    stamp = NaiveDateTime.utc_now()

    Dawarich.Test.SeedIds.insert_all!(Repo, "active_storage_blobs", [
      blob(blob_id, filename, byte_size, stamp)
    ])

    Dawarich.Test.SeedIds.insert_all!(Repo, "active_storage_attachments", [
      %{
        name: name,
        record_type: record_type,
        record_id: record_id,
        blob_id: blob_id,
        created_at: stamp
      }
    ])
  end

  def load!(seed, now) do
    for u <- seed["users"],
        do: RailsUser.insert!(%{id: u["id"], email: u["email"], settings: u["settings"]})

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "imports",
      for r <- seed["imports"] do
        %{
          id: r["id"],
          user_id: r["user_id"],
          name: r["name"],
          source: r["source"],
          status: r["status"],
          processed: r["processed"],
          doubles: r["doubles"],
          demo: r["demo"],
          error_message: r["error_message"],
          additional_data_extraction_status: r["additional_data_extraction_status"],
          created_at: time!(r["created_at"]),
          updated_at: NaiveDateTime.add(now, -r["updated_offset"])
        }
      end
    )

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "exports",
      for r <- seed["exports"] do
        %{
          id: r["id"],
          user_id: r["user_id"],
          name: r["name"],
          status: r["status"],
          file_format: r["file_format"],
          file_type: r["file_type"],
          url: r["url"],
          error_message: r["error_message"],
          created_at: time!(r["created_at"]),
          updated_at: time!(r["created_at"])
        }
      end
    )

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "active_storage_blobs",
      for(b <- seed["blobs"], do: blob(b["id"], b["filename"], b["byte_size"], now))
    )

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "active_storage_attachments",
      for a <- seed["attachments"] do
        %{
          id: a["id"],
          name: a["name"],
          record_type: a["record_type"],
          record_id: a["record_id"],
          blob_id: a["blob_id"],
          created_at: now
        }
      end
    )
  end

  defp blob(id, filename, byte_size, stamp),
    do: %{
      id: id,
      key: "a7-#{id}",
      filename: filename,
      content_type: "application/octet-stream",
      metadata: "{}",
      service_name: "test",
      byte_size: byte_size,
      checksum: "a7",
      created_at: stamp
    }

  defp time!(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.to_naive(at)
  end
end
