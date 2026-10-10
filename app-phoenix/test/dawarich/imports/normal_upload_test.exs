defmodule Dawarich.Imports.NormalUploadTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.UploadCreate
  alias Dawarich.Jobs.Ownership

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "normal-upload-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)

    rows(
      "UPDATE users SET active_until=now()+interval '1 day',status=0,settings=$2 WHERE id=$1",
      [c.import.user_id, %{"timezone" => "Berlin"}]
    )

    Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      user: %{id: c.import.user_id},
      context: %{storage: %{service: "local", root: root}, self_hosted?: true}
    }
  end

  defp upload(c, name, bytes),
    do:
      Dawarich.RailsBlobFixture.create!(ScratchRepo, c.context.storage.root, name, bytes,
        user_id: c.user.id
      )

  test "normal mixed upload preserves limits signed ids and captured zone", c do
    gpx = upload(c, "route.gpx", "<gpx/>")
    csv = upload(c, "points.csv", "latitude,longitude,timestamp\n52,13,1700000000\n")
    files = [gpx.signed_id, csv.signed_id]
    rows("UPDATE users SET status=2,subscription_source=0 WHERE id=$1", [c.user.id])

    for n <- 1..3 do
      rows(
        "INSERT INTO imports(user_id,name,source,created_at,updated_at) VALUES($1,$2,10,now(),now())",
        [c.user.id, "existing#{n}"]
      )
    end

    assert {:error, :import_limit} = UploadCreate.create(ScratchRepo, c.user, files, c.context)
    assert [] == rows("SELECT id FROM active_storage_attachments")
    rows("DELETE FROM imports WHERE name='existing3'")

    assert {:error, :invalid_token} =
             UploadCreate.create(ScratchRepo, c.user, [gpx.signed_id, "forged"], c.context)

    missing = Dawarich.RailsMessages.blob_id(9_999_999)

    assert {:error, :not_found} =
             UploadCreate.create(ScratchRepo, c.user, [gpx.signed_id, missing], c.context)

    assert {:ok, [gpx_id, csv_id]} = UploadCreate.create(ScratchRepo, c.user, files, c.context)

    assert [[4], [10]] ==
             rows("SELECT source FROM imports WHERE id=ANY($1) ORDER BY id", [[gpx_id, csv_id]])

    assert [["Berlin"], ["Berlin"]] ==
             rows("SELECT payload->>'time_zone' FROM job_outbox ORDER BY aggregate_id")

    rows("UPDATE users SET status=0 WHERE id=$1", [c.user.id])
    fresh = upload(c, "fresh.csv", "latitude,longitude\n52,13\n")

    assert {:error, :already_attached} =
             UploadCreate.create(ScratchRepo, c.user, [fresh.signed_id, csv.signed_id], c.context)

    assert [[2]] == rows("SELECT count(*) FROM active_storage_attachments")
    assert [[5]] == rows("SELECT count(*) FROM imports WHERE user_id=$1", [c.user.id])
  end

  test "upload owner chooses GPX normal or archive command atomically", c do
    Ownership.put!(ScratchRepo, "command:users.import_data", :oban)
    gpx = upload(c, "route.gpx", "<gpx/>")
    csv = upload(c, "points.csv", "latitude,longitude\n52,13\n")

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"archive.zip",
        [{~c"one.csv", "latitude,longitude\n52,13\n"}, {~c"two.gpx", "<gpx/>"}],
        [:memory]
      )

    zip = upload(c, "archive.zip", bytes)

    {:ok, {_, profile_bytes}} =
      :zip.create(
        ~c"backup.zip",
        [{~c"data.json", ~s({"counts":{},"settings":{}})}, {~c"files/a.csv", "x"}],
        [:memory]
      )

    profile = upload(c, "backup.zip", profile_bytes)

    assert {:ok, [gpx_id, csv_id, zip_id, profile_id]} =
             UploadCreate.create(
               ScratchRepo,
               c.user,
               Enum.map([gpx, csv, zip, profile], & &1.signed_id),
               c.context
             )

    assert [
             ["imports.process_gpx"],
             ["imports.process_normal"],
             ["imports.process_normal"],
             ["users.import_data"]
           ] == rows("SELECT command_type FROM job_outbox ORDER BY aggregate_id")

    assert [[4]] ==
             rows("SELECT count(*) FROM active_storage_attachments WHERE record_id=ANY($1)", [
               [gpx_id, csv_id, zip_id, profile_id]
             ])

    assert [] == rows("SELECT id FROM phoenix.rails_commands")

    Ownership.put!(ScratchRepo, "command:imports.process_normal", :sidekiq)
    other = upload(c, "reverse.csv", "latitude,longitude\n52,13\n")
    assert {:ok, [id]} = UploadCreate.create(ScratchRepo, c.user, [other.signed_id], c.context)
    assert [] == rows("SELECT event_id FROM job_outbox WHERE aggregate_id=$1", [id])

    assert [["imports.upload_created", %{"import_id" => ^id, "time_zone" => "Berlin"}]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")
  end
end

defmodule DawarichWeb.NormalUploadReplayTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser

  test "unsupported upload replay has no committed import effect" do
    user = RailsUser.insert!(%{id: 7591, email: "normal-replay@example.test"})
    session = RailsUser.session(user.id)
    root = Path.join(System.tmp_dir!(), "normal-replay-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    gpx = Dawarich.RailsBlobFixture.create!(Repo, root, "first.gpx", "<gpx/>", user_id: user.id)

    unsupported =
      Dawarich.RailsBlobFixture.create!(Repo, root, "unknown.json", "{}", user_id: user.id)

    body =
      Plug.Conn.Query.encode(%{"import" => %{"files" => [gpx.signed_id, unsupported.signed_id]}})

    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, previous) end)

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> dispatch(DawarichWeb.Endpoint, :post, "/imports", body)

    assert conn.status == 422
    assert get_resp_header(conn, "location") == ["http://www.example.com/imports/new"]
    assert [] == Repo.query!("SELECT id FROM imports").rows
    assert [] == Repo.query!("SELECT id FROM active_storage_attachments").rows
    assert [] == Repo.query!("SELECT event_id FROM job_outbox").rows
    assert [] == Repo.query!("SELECT id FROM phoenix.rails_commands").rows
  end
end
