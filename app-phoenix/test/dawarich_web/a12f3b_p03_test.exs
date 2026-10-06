defmodule DawarichWeb.A12f3bP03Test do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Jobs.{Dispatch, Ownership}
  alias Dawarich.Posters.{Persistence, Generation, ProgressWorker, PurgeWorker}
  alias Dawarich.Storage

  setup do
    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)
    root = Path.join(System.tmp_dir!(), "poster-producer-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(1,'producer@dawarich.test',now(),now())"
    )

    Ownership.put!(ScratchRepo, "command:posters.create", :oban)

    %{
      storage: %{root: root, service: "local"},
      services: %{services: %{"local" => %{root: root, service: "local"}}}
    }
  end

  @tag a12f3b_case: "P03a"
  test "poster producers finish without a Rails poller", c do
    {:ok, id} =
      Persistence.create(
        %{
          "name" => "Native",
          "start_at" => "2026-10-03",
          "end_at" => "2026-10-04",
          "lat" => "51.3",
          "lon" => "12.3",
          "distance" => "6000"
        },
        %{id: 1},
        "de",
        ScratchRepo
      )

    start_oban(:poster_producers)
    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: :poster_producers)

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.CreateWorker'")

    assert args["locale"] == "de"
    assert {:ok, _} = Ecto.UUID.cast(args["event_id"])

    for {timestamp, lon} <- [{1_791_028_860, 12.3}, {1_791_028_920, 12.3001}] do
      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES(1,$1,ST_SetSRID(ST_MakePoint($2,51.3),4326),now(),now())",
        [timestamp, lon]
      )
    end

    assert :ok =
             Generation.run(id, 1, args["event_id"], "de",
               repo: ScratchRepo,
               storage: c.storage,
               renderer: fn _, _, _ -> %{png: "synthetic", pdf: "%PDF-synthetic"} end
             )

    assert rows("SELECT status FROM posters WHERE id=$1", [id]) == [[2]]
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    progress = jobs("Dawarich.Posters.ProgressWorker")
    assert length(progress) == 3

    for job <- progress do
      assert job["locale"] == "de"
      assert :ok = ProgressWorker.run(ScratchRepo, job)
      assert :ok = ProgressWorker.run(ScratchRepo, job)
    end

    events = rows("SELECT channel,payload FROM phoenix.cable_events ORDER BY seq")
    assert length(events) == 3

    for [channel, payload] <- events do
      assert channel == Dawarich.RailsMessages.broadcasting([{:user, 1}, "posters"])
      html = Jason.decode!(payload)
      assert html =~ "action=\"replace\""
      assert html =~ "poster_#{id}"
      assert html =~ "/rails/active_storage/blobs/redirect/"
    end

    assert {:ok, ^id} = Persistence.delete(id, %{id: 1}, ScratchRepo)
    assert [purge] = jobs("Dawarich.Posters.PurgeWorker")
    assert :ok = PurgeWorker.run(ScratchRepo, purge, services: c.services)
    assert :ok = PurgeWorker.run(ScratchRepo, purge, services: c.services)
    assert rows("SELECT id FROM active_storage_blobs") == []
    assert Path.wildcard(c.storage.root <> "/**/*") |> Enum.filter(&File.regular?/1) == []
    Ownership.put!(ScratchRepo, "command:posters.create", :sidekiq, pinned: true)
    assert {:ok, fallback} = Persistence.create(%{}, %{id: 1}, "en", ScratchRepo)

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["posters.created", %{"poster_id" => fallback, "user_id" => 1, "locale" => "en"}]
           ]
  end

  @tag a12f3b_case: "P03b"
  test "poster purge cannot remove a blob still referenced elsewhere", c do
    {:ok, first} = Persistence.create(%{}, %{id: 1}, "en", ScratchRepo)
    {:ok, second} = Persistence.create(%{}, %{id: 1}, "en", ScratchRepo)
    path = Path.join(c.storage.root, "object")
    File.mkdir_p!(c.storage.root)
    File.write!(path, "synthetic")
    blob = Storage.put!(c.storage, path, "poster.png", "image/png")

    [[blob_id]] =
      rows(
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
      )

    for id <- [first, second],
        do:
          rows(
            "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('image','Poster',$1,$2,now())",
            [id, blob_id]
          )

    assert {:ok, ^first} = Persistence.delete(first, %{id: 1}, ScratchRepo)
    assert [purge] = jobs("Dawarich.Posters.PurgeWorker")
    assert :ok = PurgeWorker.run(ScratchRepo, purge, services: c.services)
    assert Storage.get!(c.storage, blob.key) == "synthetic"
    assert rows("SELECT id FROM active_storage_blobs") == [[blob_id]]
    assert {:ok, ^second} = Persistence.delete(second, %{id: 1}, ScratchRepo)
    orphan = jobs("Dawarich.Posters.PurgeWorker") |> List.last()
    blocked = %{services: %{"local" => %{root: c.storage.root, service: "local"}}}
    file = Storage.disk_path(c.storage.root, blob.key)
    File.rm!(file)
    File.mkdir!(file)

    assert {:error, {:storage_delete, :eperm}} =
             PurgeWorker.run(ScratchRepo, orphan, services: blocked)

    assert rows("SELECT id FROM active_storage_blobs") == []
    File.rmdir!(file)
    File.write!(file, "synthetic")
    assert :ok = PurgeWorker.run(ScratchRepo, orphan, services: c.services)
    assert rows("SELECT id FROM active_storage_blobs") == []
    assert File.read!(file) == "synthetic"
  end

  defp jobs(worker),
    do:
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [worker])
      |> List.flatten()
end
