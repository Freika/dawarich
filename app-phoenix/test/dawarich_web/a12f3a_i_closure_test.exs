defmodule DawarichWeb.A12f3aIClosureTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{ImportsExportsSeeds, RailsUser}
  alias Dawarich.Jobs.Ownership

  setup do
    user = RailsUser.insert!(%{id: 7811, email: "closure-import@example.test"})
    session = RailsUser.session(user.id)
    root = Path.join(System.tmp_dir!(), "imports-closure-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})
    Ownership.put!(Repo, "command:imports.process_gpx", :oban)
    Ownership.put!(Repo, "command:imports.process_normal", :oban)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, previous)
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    %{user: user, session: session, root: root}
  end

  @tag a12f3a_i02: true
  test "I02: upload forms and signed/raw files matches current Rails contract without a native-owner Rails effect",
       c do
    for {files, expected} <- Enum.zip([nil, [], [""]], capture("i02")) do
      params = if is_nil(files), do: %{}, else: %{"import" => %{"files" => files}}
      response = request(c, :post, "/imports", params)
      assert response.status == expected["status"]
      assert get_resp_header(response, "location") == [expected["location"]]

      assert Dawarich.Test.RailsFormRequests.rails_session(response)["flash"]["flashes"]["alert"] ==
               expected["alert"]

      assert Repo.query!("SELECT count(*) FROM imports").rows == [[0]]
    end

    blob =
      Dawarich.RailsBlobFixture.create!(Repo, c.root, "Leipzig.gpx", "<gpx/>", user_id: c.user.id)

    rejected =
      request(c, :post, "/imports", %{"import" => %{"files" => [blob.signed_id, "invalid"]}})

    assert rejected.status == 422
    assert Repo.query!("SELECT count(*) FROM imports").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM active_storage_attachments").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]

    response = request(c, :post, "/imports", %{"import" => %{"files" => [blob.signed_id]}})
    assert response.status == 303
    assert Repo.query!("SELECT name,source FROM imports").rows == [["Leipzig.gpx", 4]]
    assert Repo.query!("SELECT command_type FROM job_outbox").rows == [["imports.process_gpx"]]
    assert commands() == []
  end

  @tag a12f3a_i03: true
  test "I03: import rename source and put updates matches current Rails contract without a native-owner Rails effect",
       c do
    ImportsExportsSeeds.import!(%{
      id: 781_101,
      user_id: c.user.id,
      name: "normal.csv",
      source: 10
    })

    for {method, params, expected} <- [
          {:put, %{"name" => "renamed.csv", "source" => "geojson"}, ["renamed.csv", 6]},
          {:patch, %{"name" => "", "source" => "gpx"}, ["renamed.csv", 6]},
          {:post, %{"name" => "override.csv", "source" => "gpx"}, ["override.csv", 4]}
        ] do
      body = %{"import" => params}
      body = if method == :post, do: Map.put(body, "_method", "put"), else: body
      response = request(c, method, "/imports/781101", body)
      assert response.status == 303
      assert get_resp_header(response, "location") == ["http://www.example.com/imports"]
      assert Repo.query!("SELECT name,source FROM imports WHERE id=781101").rows == [expected]
    end

    invalid = request(c, :put, "/imports/781101", %{"import" => %{"source" => "unknown"}})
    assert invalid.status == 422
    assert invalid.resp_body =~ "Source"

    assert Repo.query!("SELECT name,source FROM imports WHERE id=781101").rows == [
             ["override.csv", 4]
           ]

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert commands() == []
  end

  @tag a12f3a_i04: true
  test "I04: delete and extraction request transitions matches current Rails contract without a native-owner Rails effect",
       c do
    ImportsExportsSeeds.import!(%{
      id: 781_104,
      user_id: c.user.id,
      name: "extract.gpx",
      status: 2,
      raw_data: %{"waypoints_seen" => 1}
    })

    Ownership.put!(Repo, "command:enhanced_import.extract_gpx", :oban)
    Ownership.put!(Repo, "command:enhanced_import.destroy_gpx", :oban)

    assert request(c, :post, "/imports/781104/extraction", %{"trust_source" => "false"}).status ==
             302

    assert [[payload]] =
             Repo.query!(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'"
             ).rows

    assert %{
             "import_id" => 781_104,
             "lock_attempt" => 1,
             "user_id" => 7811,
             "source" => 4,
             "source_blob_id" => nil
           } = payload

    assert [[payload["event_id"], payload["started_at"]]] ==
             Repo.query!(
               "SELECT additional_data_extraction->>'phoenix_extraction_event',additional_data_extraction->>'started_at' FROM imports WHERE id=781104"
             ).rows

    assert commands() == []
    assert request(c, :post, "/imports/781104/extraction", %{}).status == 303
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]

    assert Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'"
           ).rows == [[1]]

    Repo.query!("UPDATE imports SET additional_data_extraction_status=3 WHERE id=781104")
    assert request(c, :delete, "/imports/781104/extraction", %{}).status == 302

    assert Repo.query!("SELECT command_type FROM job_outbox ORDER BY command_type DESC").rows == [
             ["enhanced_import.destroy_gpx"]
           ]

    assert Repo.query!("SELECT additional_data_extraction_status FROM imports WHERE id=781104").rows ==
             [[2]]

    assert commands() == []
  end

  defp capture(task) do
    Path.expand("../fixtures/imports_pages/a12f3a-#{task}.json", __DIR__)
    |> File.read!()
    |> Jason.decode!()
  end

  @tag a12f3a_i05: true
  test "I05: import original and prepared downloads matches current Rails contract without a native-owner Rails effect",
       c do
    oracle = capture("i05")
    {:ok, {_, zip}} = :zip.create(~c"wrapped.zip", [{~c"wrapped.gpx", "<gpx/>"}], [:memory])

    blob =
      Dawarich.RailsBlobFixture.create!(Repo, c.root, "wrapped.gpx.zip", zip, user_id: c.user.id)

    descriptor = %{
      "signed_id" => blob.signed_id,
      "client_wrapped" => true,
      "original_filename" => "wrapped.gpx"
    }

    Ownership.put!(Repo, "command:imports.prepare_download", :oban)
    Ownership.put!(Repo, "command:imports.prepared_download_purge", :oban)

    {:ok, [id]} =
      Dawarich.Imports.UploadCreate.create(Repo, c.user, [descriptor], %{
        storage: %{service: "local", root: c.root},
        self_hosted?: true
      })

    stale =
      Dawarich.RailsBlobFixture.create!(Repo, c.root, "stale.gpx", "stale",
        metadata: %{"dawarich_download_source_blob_id" => blob.id + 1}
      )

    Repo.query!(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'prepared_download',$2,now())",
      [id, stale.id]
    )

    response = request(c, :get, "/imports/#{id}/download", %{})
    assert response.status == oracle["status"]
    assert get_resp_header(response, "refresh") == [oracle["refresh"]]

    assert Repo.query!(
             "SELECT payload FROM job_outbox WHERE command_type='imports.prepare_download'"
           ).rows == [[%{"import_id" => id, "user_id" => c.user.id, "source_blob_id" => blob.id}]]

    original = request(c, :get, "/imports/#{id}/download?original=1", %{})
    assert original.status == 200
    assert original.resp_body == zip
    assert hd(get_resp_header(original, "content-disposition")) =~ oracle["original_filename"]

    for key <- [:imports_storage, :imports_services, :jobs_repo] do
      previous = Application.fetch_env(:dawarich, key)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:dawarich, key, value)
          :error -> Application.delete_env(:dawarich, key)
        end
      end)
    end

    Application.delete_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_services, %{})
    unavailable = request(c, :get, "/imports/#{id}/download?original=1", %{})
    assert unavailable.status == 422
    assert get_resp_header(unavailable, "x-dawarich-handler") == ["phoenix-imports"]
    Application.put_env(:dawarich, :jobs_repo, Repo)

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "import_id" => id,
      "user_id" => c.user.id,
      "source_blob_id" => blob.id
    }

    [[job_id]] =
      Repo.query!(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.PrepareDownloadWorker',$1,1,3,now()) RETURNING id",
        [args]
      ).rows

    job = %Oban.Job{id: job_id, attempt: 1, args: args}

    assert {:error, :unconfigured_storage_service} =
             Dawarich.Imports.PrepareDownloadWorker.perform(job)

    refute Dawarich.Jobs.Processed.done?(Repo, args["event_id"])
    assert commands() == []

    Application.put_env(:dawarich, :imports_services, %{
      "local" => %{service: "local", root: c.root}
    })

    assert :ok = Dawarich.Imports.PrepareDownloadWorker.perform(job)
    assert Dawarich.Jobs.Processed.done?(Repo, args["event_id"])
    prepared = request(c, :get, "/imports/#{id}/download", %{})
    assert prepared.status == 200
    assert prepared.resp_body == "<gpx/>"
    assert request(c, :get, "/imports/#{id}/download?original=1", %{}).resp_body == zip
    assert commands() == []
  end

  defp request(c, method, path, params) do
    body = Plug.Conn.Query.encode(params)

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(c.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end
end

defmodule DawarichWeb.A12f3aINativePurgeTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{ImportBlobPurges, ImportBlobPurgeWorker}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed}

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [c.job.id])
    root = Path.join(System.tmp_dir!(), "import-purge-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)

    for {key, value} <- [
          jobs_repo: ScratchRepo,
          imports_services: %{"local" => %{service: "local", root: root}}
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
    Ownership.put!(ScratchRepo, "command:imports.prepared_download_purge", :oban)
    Map.put(c, :root, root)
  end

  @tag a12f3a_i06_purge: true
  test "I06 priority: native detached blob purge uses immutable receipts and preserves reattached blobs",
       c do
    oracle =
      Path.expand("../fixtures/imports_pages/a12f3a-i06.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()
      |> Map.new(&{&1["name"], &1["jobs"]})

    assert oracle["authorized"] == ["ActiveStorage::PurgeJob"]
    assert oracle["missing_receipt"] == []
    assert oracle["foreign_actor"] == []
    assert oracle["attached_blob"] == []
    source = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "source.gpx", "<gpx/>")

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
      [c.import.id, source.id]
    )

    old = detached(c, source.id)
    assert rows("SELECT command_type FROM job_outbox") == [["imports.prepared_download_purge"]]
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    start_oban(__MODULE__)

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               oban: __MODULE__,
               repo: ScratchRepo
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [old.id]) == []
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [source.id]) == [[source.id]]
    shared = detached(c, source.id)

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('User',$1,'avatar',$2,now())",
      [c.other, shared.id]
    )

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               oban: __MODULE__,
               repo: ScratchRepo
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared.id]) == [[shared.id]]

    assert rows("SELECT count(*) FROM active_storage_attachments WHERE blob_id=$1", [shared.id]) ==
             [[1]]

    assert bytes(c, shared.id) == "old"
    rejected = detached(c, source.id)

    rows(
      "INSERT INTO phoenix.import_blob_purges(blob_id,import_id,user_id,source_blob_id) VALUES($1,$2,$3,$4)",
      [rejected.id, c.import.id, c.other, source.id]
    )

    payload = payload(c, source.id, rejected.id) |> Map.put("user_id", c.other)
    j = job(payload)
    assert :ok = ImportBlobPurgeWorker.perform(j)
    assert Processed.done?(ScratchRepo, j.args["event_id"])

    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [rejected.id]) == [
             [rejected.id]
           ]

    assert bytes(c, rejected.id) == "old"
    no_receipt = job(payload(c, source.id + 1, rejected.id))
    assert :ok = ImportBlobPurgeWorker.perform(no_receipt)
    assert bytes(c, rejected.id) == "old"
    j = job(payload(c, source.id, rejected.id))
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [j.id])
    assert {:cancel, _} = ImportBlobPurgeWorker.perform(j)
    refute Processed.done?(ScratchRepo, j.args["event_id"])
    assert :ok = ImportBlobPurgeWorker.perform(%{j | attempt: 2})
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [rejected.id]) == []
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    retry = detached(c, source.id)
    j = job(payload(c, source.id, retry.id))
    services = Application.get_env(:dawarich, :imports_services)
    Application.put_env(:dawarich, :imports_services, %{})
    assert {:error, :unconfigured_storage_service} = ImportBlobPurgeWorker.perform(j)
    refute Processed.done?(ScratchRepo, j.args["event_id"])
    assert bytes(c, retry.id) == "old"
    Application.put_env(:dawarich, :imports_services, services)
    assert :ok = ImportBlobPurgeWorker.perform(j)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [retry.id]) == []
    handback = detached(c, source.id)
    Ownership.put!(ScratchRepo, "command:imports.prepared_download_purge", :sidekiq)
    j = job(payload(c, source.id, handback.id))
    assert :ok = ImportBlobPurgeWorker.perform(j)
    assert :ok = ImportBlobPurgeWorker.perform(j)
    assert bytes(c, handback.id) == "old"

    assert rows("SELECT kind FROM phoenix.rails_commands") == [
             ["imports.prepared_download_purge"]
           ]

    valid = payload(c, source.id, handback.id)
    assert {:ok, ^valid} = ImportBlobPurgeWorker.args_from_command(1, valid)

    assert {:error, "invalid_payload"} =
             ImportBlobPurgeWorker.args_from_command(1, Map.put(valid, "extra", true))

    assert {:error, "invalid_payload"} =
             ImportBlobPurgeWorker.args_from_command(1, Map.put(valid, "blob_id", 0))

    assert {:error, "unsupported_version"} = ImportBlobPurgeWorker.args_from_command(2, valid)
  end

  defp bytes(c, id) do
    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [id])
    File.read!(Dawarich.Storage.disk_path(c.root, key))
  end

  defp detached(c, source) do
    blob = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "old.gpx", "old")

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'prepared_download',$2,now())",
      [c.import.id, blob.id]
    )

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               ImportBlobPurges.authorize!(
                 ScratchRepo,
                 c.import.id,
                 c.import.user_id,
                 blob.id,
                 source
               )

               outbox!(
                 command_type: "imports.prepared_download_purge",
                 payload: payload(c, source, blob.id)
               )

               rows(
                 "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND blob_id=$2",
                 [c.import.id, blob.id]
               )

               :ok
             end)

    blob
  end

  defp payload(c, source, blob),
    do: %{
      "blob_id" => blob,
      "import_id" => c.import.id,
      "user_id" => c.import.user_id,
      "source_blob_id" => source
    }

  defp job(payload) do
    args = Map.put(payload, "event_id", Ecto.UUID.generate())

    [[id]] =
      rows(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.ImportBlobPurgeWorker',$1,1,3,now()) RETURNING id",
        [args]
      )

    %Oban.Job{id: id, attempt: 1, args: args}
  end
end

defmodule DawarichWeb.A12f3aIProducerClosureTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Teslamate.Effects
  alias Dawarich.Jobs.Ownership

  @tag a12f3a_i09: true
  test "I09: teslamate import producer matches current Rails contract without a native-owner Rails effect" do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{
          id: 7819,
          email: "teslamate-closure@example.test",
          settings: %{"timezone" => "UTC", "gps_filtering_enabled" => false}
        },
        ScratchRepo
      )

    for key <- ~w(tracks.generate_realtime tracks.backfill),
        do: Ownership.put!(ScratchRepo, "command:" <> key, :oban)

    ctx = %{
      repo: ScratchRepo,
      id: user.id,
      settings: user.settings,
      event: Ecto.UUID.generate(),
      now: ~U[2026-01-15 23:30:00Z]
    }

    acc = %{range: {1_768_000_000, 1_768_000_100}, months: [{2026, 1}]}
    assert {:ok, :ok} = ScratchRepo.transaction(fn -> Effects.finalize(ctx, acc) end)

    assert rows("SELECT command_type FROM job_outbox ORDER BY command_type") == [
             ["tracks.backfill"],
             ["tracks.generate_realtime"]
           ]

    assert rows("SELECT kind FROM phoenix.rails_commands") == [["stats.calculate_month"]]

    assert [[payload]] =
             rows("SELECT payload FROM job_outbox WHERE command_type='tracks.generate_realtime'")

    assert payload == %{"user_id" => user.id}
    assert {:ok, :ok} = ScratchRepo.transaction(fn -> Effects.finalize(ctx, acc) end)

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='tracks.generate_realtime'") ==
             [[1]]

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='tracks.backfill'") == [[1]]
  end
end
