defmodule DawarichWeb.ImportsDownloadPipelineTest do
  use Dawarich.JobsCase
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  alias Dawarich.Jobs.{Ownership, Dispatch, Processed}
  @endpoint DawarichWeb.Endpoint

  test "native HTTP pending request dispatches the real worker and streams the prepared bytes" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    c = Dawarich.ImportLeaseFixture.create()

    user =
      RailsUser.insert!(%{id: c.import.user_id, email: "http-download-pipeline@example.test"})

    root = Path.join(System.tmp_dir!(), "http-pipeline-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    config = %{service: "local", root: root}

    for {key, value} <- [
          imports_repo: ScratchRepo,
          jobs_repo: ScratchRepo,
          imports_storage: config
        ] do
      previous = Application.fetch_env(:dawarich, key)
      Application.put_env(:dawarich, key, value)

      on_exit(fn ->
        case previous do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "command:imports.prepare_download", :oban)
    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [c.job.id])
    bytes = "<gpx><wpt lat=\"52.5\" lon=\"13.4\"/></gpx>"
    path = Path.join(root, "input.zip")
    Dawarich.GpxZipFixture.write!(path, [{"ride.gpx", bytes, [method: 8]}])
    blob = Dawarich.Storage.put!(config, path, "ride.gpx.zip", "application/zip")

    metadata =
      Jason.encode!(%{
        "dawarich_client_wrapped" => true,
        "dawarich_original_filename" => "ride.gpx"
      })

    [[blob_id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,metadata,created_at) VALUES($1,$2,$3,$4,$5,$6,now()) RETURNING id",
        [blob.key, blob.filename, blob.byte_size, blob.checksum, blob.service_name, metadata]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
      [c.import.id, blob_id]
    )

    url = "/imports/#{c.import.id}/download"
    conn = get(RailsUser.signed_in(user.id), url)
    assert conn.status == 202
    assert Plug.Conn.get_resp_header(conn, "refresh") == ["3"]

    [[event]] =
      rows("SELECT event_id::text FROM job_outbox WHERE command_type='imports.prepare_download'")

    start_oban(__MODULE__)

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               oban: __MODULE__,
               repo: ScratchRepo
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)
    assert Processed.done?(ScratchRepo, event)
    conn = get(RailsUser.signed_in(user.id), url)
    assert conn.status == 200
    assert conn.resp_body == bytes
    assert Plug.Conn.get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
    assert hd(Plug.Conn.get_resp_header(conn, "content-disposition")) =~ "lease.gpx"

    assert [[1]] =
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )
  end
end
