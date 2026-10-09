defmodule DawarichWeb.A12f3aERequestClosureTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{
      id: 9721,
      email: "exports-closure@example.test",
      settings: %{"timezone" => "UTC", "locale" => "en"}
    })

    Ownership.put!(Repo, "command:exports.points", :oban)
    session = RailsUser.session(9721)
    %{session: session, token: DawarichWeb.RailsCsrf.masked_token(session)}
  end

  @tag a12f3a_e01: true
  test "E01: export index and format submission matches current Rails contract without a native-owner Rails effect",
       c do
    capture = File.read!("test/fixtures/user_data/a12f3a-e02.json") |> Jason.decode!()

    cases =
      Enum.filter(
        capture["cases"] ++ capture["containers"],
        &(&1["source"] == "hand" and
            &1["name"] not in ["method override to delete", "client parameter"])
      )

    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    for hosted <- ["true", "false", nil], data <- cases do
      if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")
      Repo.query!("DELETE FROM exports")
      Repo.query!("DELETE FROM job_outbox")
      body = Plug.Conn.Query.encode(data["params"])
      conn = post_form(c.session, body, [{"x-csrf-token", c.token}], data["path"] || "/exports")
      expected = data["rails"]
      assert conn.status == expected["status"], data["name"]
      assert conn.resp_body == ""
      assert get_resp_header(conn, "location") == [expected["headers"]["location"]]
      assert Map.has_key?(conn.resp_cookies, "_dawarich_session"), data["name"]
      assert rails_session(conn)["flash"]["flashes"] == expected["flash"]

      columns =
        ~w(name status file_format file_type start_at end_at url error_message processing_started_at)

      actual = Repo.query!("SELECT #{Enum.join(columns, ",")} FROM exports").rows
      actual = Enum.map(actual, fn row -> Map.new(Enum.zip(columns, Enum.map(row, &iso/1))) end)
      assert actual == List.wrap(expected["export"]), data["name"] <> " " <> inspect(actual)
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[expected["export_jobs"]]]
      assert commands() == []
    end

    Repo.query!("DELETE FROM exports")
    seed = File.read!("test/fixtures/imports_exports/seed.json") |> Jason.decode!()
    Dawarich.Test.ImportsExportsSeeds.load!(seed, NaiveDateTime.utc_now())
    pages = File.read!("test/fixtures/imports_exports/pages.json") |> Jason.decode!()
    index = File.read!("test/fixtures/user_data/a12f3a-e01.json") |> Jason.decode!()

    for {name, expected} <- index do
      page = Enum.find(pages, &(&1["name"] == name))

      conn =
        Phoenix.ConnTest.dispatch(
          RailsUser.signed_in(page["user_id"]),
          DawarichWeb.Endpoint,
          :get,
          page["path"],
          nil
        )

      assert conn.status == expected["status"]

      assert Dawarich.Test.ParityHTML.fragment(conn.resp_body, "div.px-4.flex-1 > div.flex > *") ==
               Dawarich.Test.ParityHTML.normalize(expected["body"])
    end
  end

  @tag a12f3a_e04: true
  @tag :tmp_dir
  test "E04: backup http producer and authority matches current Rails contract without a native-owner Rails effect",
       c do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Ownership.put!(Repo, "command:users.export_data", :oban)
    Ownership.put!(Repo, "command:users.import_data", :oban)

    expected =
      File.read!("test/fixtures/user_data/a12f3a-e04.json")
      |> Jason.decode!()
      |> get_in(["summary", "en"])

    owner = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(9721), "en")
    assert :ok = Dawarich.UserData.request_export(owner)

    assert [[%{"user_id" => 9721}]] =
             Repo.query!("SELECT payload FROM job_outbox WHERE command_type='users.export_data'").rows

    for {kind, value} <- [{"array", ["x"]}, {"object", %{"nested" => "x"}}] do
      assert {:error, :invalid_archive} = Dawarich.UserData.start_import(owner, value)

      assert expected["containers"][kind]["flash"] == %{
               "alert" =>
                 DawarichWeb.Translate.t(
                   "en",
                   "controllers.settings.users.an_error_occurred_while_starting_the_import_please_try_again",
                   %{}
                 )
             }
    end

    Repo.query!(
      "UPDATE users SET settings=settings||'{\"gps_filtering_enabled\":false}'::jsonb,points_count=1 WHERE id=9721"
    )

    Repo.query!(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES(9721,1767225600,ST_GeomFromText('POINT(12.4 51.3)',4326),now(),now())"
    )

    [[event, payload]] =
      Repo.query!(
        "SELECT event_id::text,payload FROM job_outbox WHERE command_type='users.export_data'"
      ).rows

    storage = %{service: "local", root: c.tmp_dir}

    context = %{
      repo: Repo,
      storage: storage,
      storage_services: %{"local" => storage},
      zone: "UTC",
      locale: "en",
      now: ~N[2026-10-02 12:00:00],
      temp_dir: c.tmp_dir,
      application_zone: "Europe/Berlin"
    }

    assert :ok ==
             Dawarich.UserData.ExportWorker.run(Repo, Map.put(payload, "event_id", event),
               context: context
             )

    [[blob_id, key]] =
      Repo.query!(
        "SELECT b.id,b.key FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_type='Export'"
      ).rows

    {:ok, entries} =
      :zip.unzip(String.to_charlist(Dawarich.Storage.disk_path(c.tmp_dir, key)), [:memory])

    manifest = entries |> Map.new() |> Map.fetch!(~c"manifest.json") |> Jason.decode!()
    assert manifest["counts"]["points"] == 1
    signed_id = Dawarich.RailsMessages.blob_id(blob_id)
    foreign = RailsUser.insert!(%{id: 9722, email: "foreign-backup@example.test"})

    assert {:error, :invalid_archive} =
             Dawarich.UserData.start_import(
               Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(foreign.id), "en"),
               signed_id
             )

    assert [[0]] ==
             Repo.query!("SELECT count(*) FROM job_outbox WHERE command_type='users.import_data'").rows

    assert :ok = Dawarich.UserData.start_import(owner, signed_id)

    [[import_event, import_payload]] =
      Repo.query!(
        "SELECT event_id::text,payload FROM job_outbox WHERE command_type='users.import_data'"
      ).rows

    Ecto.Migrator.run(Repo, Path.expand("priv/repo/oban_migrations"), :up,
      all: true,
      prefix: "oban",
      log: false
    )

    args = Map.put(import_payload, "event_id", import_event)

    {1, [%{id: job_id}]} =
      Repo.insert_all(
        "oban_jobs",
        [
          %{
            state: "executing",
            queue: "imports",
            worker: "Dawarich.UserData.ImportWorker",
            args: args,
            attempt: 1,
            max_attempts: 1
          }
        ],
        prefix: "oban",
        returning: [:id]
      )

    Repo.query!("DELETE FROM points WHERE user_id=9721")

    assert :ok ==
             Dawarich.UserData.ImportWorker.run(
               Repo,
               %Oban.Job{id: job_id, args: args, attempt: 1},
               context: context
             )

    assert [[1]] == Repo.query!("SELECT count(*) FROM points WHERE user_id=9721").rows
    assert [[1]] == Repo.query!("SELECT points_count FROM users WHERE id=9721").rows
    assert commands() == []
  end

  @tag a12f3a_e03: true
  @tag :tmp_dir
  test "E03: export delete and native purge matches current Rails contract without a native-owner Rails effect",
       c do
    Ecto.Migrator.run(Repo, Path.expand("priv/repo/oban_migrations"), :up,
      all: true,
      prefix: "oban",
      log: false
    )

    RailsUser.insert!(%{id: 9722, email: "foreign-closure@example.test"})

    Repo.query!(
      "INSERT INTO exports(id,user_id,name,status,created_at,updated_at) VALUES(972101,9721,'synthetic.zip',2,now(),now()),(972102,9722,'shared.zip',2,now(),now())"
    )

    blob = Dawarich.RailsBlobFixture.create!(Repo, c.tmp_dir, "shared.zip", "synthetic bytes")

    for id <- [972_101, 972_102],
        do:
          Repo.query!(
            "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',$1,$2,now())",
            [id, blob.id]
          )

    assert post_form(c.session, "_method=DELETE", [{"x-csrf-token", c.token}], "/exports/972102").status ==
             404

    conn = post_form(c.session, "_method=DELETE", [{"x-csrf-token", c.token}], "/exports/972101")
    assert conn.status == 303

    assert rails_session(conn)["flash"]["flashes"] == %{
             "notice" => "Export was successfully destroyed."
           }

    assert [[blob.id]] ==
             Repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id]).rows

    assert [] ==
             Repo.query!(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'"
             ).rows

    assert commands() == []
  end

  defp iso(%NaiveDateTime{} = value),
    do: NaiveDateTime.to_iso8601(%{value | microsecond: {elem(value.microsecond, 0), 6}}) <> "Z"

  defp iso(value), do: value
end

defmodule DawarichWeb.A12f3aEWorkerClosureTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.{Export, ExportWorker, ImportWorker, Restore, Archive, Paths, Versions}
  alias Dawarich.Jobs.{Ownership, Processed}
  @moduletag :tmp_dir

  setup do
    clean()
    :ok
  end

  @tag a12f3a_e02: true
  test "E02: export serialization and native job producer matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    capture = File.read!("test/fixtures/user_data/a12f3a-e02.json") |> Jason.decode!()
    rows("DELETE FROM points")

    rows(
      "INSERT INTO points(user_id,timestamp,lonlat,altitude,altitude_decimal,created_at,updated_at) VALUES($1,1709812800,ST_GeomFromText('POINT(12.4 51.3)',4326),12,12.75,now(),now())",
      [c.user_id]
    )

    for {format, number} <- [{"json", 0}, {"gpx", 1}] do
      export = %{
        id: 1,
        user_id: c.user_id,
        name: "source.#{format}",
        file_format: number,
        start_at: 1_709_251_200,
        end_at: 1_711_843_200,
        settings: %{}
      }

      path = Path.join(dir, format)
      Dawarich.Exports.Points.write_payload!(ScratchRepo, export, path, "Europe/Berlin")
      assert File.read!(path) == capture["workers"][format]["entries"][export.name]
    end

    rows(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1709812700,ST_GeomFromText('POINT(12.5 51.4)',4326),now(),now())",
      [c.user_id]
    )

    export = %{
      id: 1,
      user_id: c.user_id,
      name: "ordered.gpx",
      file_format: 1,
      start_at: 1_709_251_200,
      end_at: 1_711_843_200,
      settings: %{}
    }

    path = Path.join(dir, "ordered")
    Dawarich.Exports.Points.write_payload!(ScratchRepo, export, path, "UTC")

    assert ["2024-03-07T11:58:20Z", "2024-03-07T12:00:00Z"] ==
             Regex.scan(~r/<time>(.*?)<\/time>/, File.read!(path), capture: :all_but_first)
             |> List.flatten()

    rows("UPDATE exports SET status=0,file_type=0,file_format=1 WHERE id=$1", [c.export_id])
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.user_id])

    assert :skip ==
             Dawarich.Exports.claim(ScratchRepo, c.export_id, c.user_id, Ecto.UUID.generate())

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  @tag a12f3a_e05: true
  test "E05: backup plain entities and settings matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    archive = Export.write(ScratchRepo, c.user_id, dir, export_context(c))
    expected = UserDataSeeds.current_export_entries("UTC")
    assert zip_entries(archive.path) == expected
    assert archive.counts == Jason.decode!(expected["manifest.json"])["counts"]
    assert Jason.decode!(expected["manifest.json"]) == capture(5)["exports"]["UTC"]["manifest"]
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  @tag a12f3a_e06: true
  test "E06: backup monthly and spatial entities matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)

    for zone <- ["UTC", "Europe/Berlin", "America/New_York"] do
      context = %{c.context | zone: zone}
      expected = UserDataSeeds.current_export_entries(zone)
      manifest = capture(6)["exports"][zone]["manifest"]
      assert manifest == Jason.decode!(expected["manifest.json"])

      for {module, name} <- [
            {Dawarich.UserData.Export.Points, "points"},
            {Dawarich.UserData.Export.Visits, "visits"},
            {Dawarich.UserData.Export.Tracks, "tracks"},
            {Dawarich.UserData.Export.Stats, "stats"},
            {Dawarich.UserData.Export.Digests, "digests"}
          ] do
        entries = module.write(ScratchRepo, c.user_id, dir, context)
        assert Enum.map(entries, & &1.name) == manifest["files"][name]
        for entry <- entries, do: assert(File.read!(entry.path) == expected[entry.name])
      end

      File.rm_rf!(dir)
      File.mkdir_p!(dir)
    end

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  @tag a12f3a_e07: true
  test "E07: backup attachments portable archives and lifecycle matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    rows("DELETE FROM exports WHERE id=$1", [c.export_id])
    args = export_args(c)
    Ownership.put!(ScratchRepo, "command:users.export_data", :oban)
    context = export_context(c) |> Map.put(:temp_dir, dir)
    assert :ok == ExportWorker.run(ScratchRepo, args, context: context)
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert :ok == ExportWorker.run(ScratchRepo, args, context: context)
    assert [[1]] == rows("SELECT count(*) FROM notifications WHERE title='Export completed'")
    next = %{args | "event_id" => Ecto.UUID.generate()}

    put = fn storage, zip, name ->
      blob = Dawarich.Storage.put!(storage, zip, name, "application/zip")
      rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.user_id])
      blob
    end

    assert {:cancel, :ownership_lost} ==
             ExportWorker.run(ScratchRepo, next, context: context, put: put)

    assert [[1]] ==
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_type='Export' AND record_id IN (SELECT export_id FROM phoenix.export_claims)"
             )

    assert File.ls!(Path.join(context.storage.root, ".phoenix-tmp")) == []
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  @tag a12f3a_e08: true
  test "E08: restore version safety and settings entities matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    assert Paths.sanitize("../outside.jsonl") == nil
    assert Paths.relative(dir, "../outside.jsonl") == nil
    c = UserDataSeeds.seed!("unsafe_paths", ScratchRepo)

    Archive.with_directory(c.archive_path, %{temp_dir: dir}, fn extracted ->
      assert Versions.detect(extracted) == 2
      assert File.regular?(Path.join(extracted, "settings.jsonl"))
      refute File.exists?(Path.join(extracted, "outside.jsonl"))
    end)

    assert [] == File.ls!(dir)
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  @tag a12f3a_e09: true
  test "E09: restore places tags and attachments matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    for name <- ["v1", "v1_reversed", "v2", "v2_root"] do
      reset!(ScratchRepo)
      clean()
      c = UserDataSeeds.seed!(name, ScratchRepo)
      Ownership.put!(ScratchRepo, "command:points.tile_epoch", :oban)

      assert Restore.call(
               ScratchRepo,
               c.user_id,
               c.archive_path,
               c.context |> Map.put(:fence, fn f -> f.() end) |> Map.put(:native_owner, true),
               filter: fn _, _, _, _, _ -> 0 end
             ) == capture(9)["restores"][name]["result"]

      assert [[c.expected["result"]["files_restored"]]] ==
               rows("SELECT count(*) FROM active_storage_attachments")

      assert [[0]] ==
               rows(
                 "SELECT count(*) FROM taggings tg JOIN tags t ON t.id=tg.tag_id JOIN places p ON p.id=tg.taggable_id WHERE p.user_id<>t.user_id"
               )

      case rows("SELECT tag_id,taggable_id FROM taggings LIMIT 1") do
        [[tag, _]] ->
          [[place]] =
            rows(
              "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'hostile target',50,40,now(),now()) RETURNING id",
              [c.user_id]
            )

          hostile = %{
            "taggable_type" => "Place",
            "tag_name" => "missing synthetic",
            "taggable_name" => "unknown synthetic",
            "taggable_id" => place,
            "tag_id" => tag,
            "taggable_latitude" => "1",
            "taggable_longitude" => "2"
          }

          assert 0 ==
                   Dawarich.UserData.Restore.Taggings.call(
                     ScratchRepo,
                     c.user_id,
                     [hostile],
                     c.context
                   )

        [] ->
          :ok
      end

      assert [[count]] =
               rows(
                 "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Points.TileEpochWorker'"
               )

      assert count > 0

      assert Enum.all?(
               rows("SELECT kind FROM phoenix.rails_commands"),
               &(&1 == ["tracks_changed"])
             )

      assert [] == File.ls!(dir)
    end
  end

  @tag a12f3a_e10: true
  test "E10: restore monthly points and raw archives matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    c = UserDataSeeds.seed!("v2", ScratchRepo)
    Ownership.put!(ScratchRepo, "command:points.tile_epoch", :oban)

    for boundary <- capture(10)["boundaries"] do
      count = boundary["count"]
      assert count == boundary["result"]["points_created"]
      rows("DELETE FROM points")
      rows("DELETE FROM oban.oban_jobs WHERE worker='Dawarich.Points.TileEpochWorker'")
      path = "test/fixtures/user_data/boundary_#{count}/entries/points.jsonl"
      stream = File.stream!(path) |> Stream.map(&Jason.decode!/1)

      assert count ==
               Dawarich.UserData.Restore.Points.call(
                 ScratchRepo,
                 c.user_id,
                 stream,
                 Map.put(c.context, :native_owner, true)
               )

      jobs =
        rows(
          "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Points.TileEpochWorker' ORDER BY id"
        )

      assert jobs != []

      for [payload] <- jobs,
          do: assert(:ok == Dawarich.Points.TileEpochWorker.run(ScratchRepo, payload))

      key = "points:tile_epoch:#{c.user_id}:2026"
      assert {:ok, epoch} = Dawarich.Redis.cache_command(["GET", key])
      assert is_binary(epoch) and Regex.match?(~r/\A[0-9a-f]{16}\z/, epoch)
      on_exit(fn -> Dawarich.Redis.cache_command(["DEL", key]) end)

      assert 0 ==
               Dawarich.UserData.Restore.Points.call(
                 ScratchRepo,
                 c.user_id,
                 stream,
                 Map.put(c.context, :native_owner, true)
               )

      assert jobs ==
               rows(
                 "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Points.TileEpochWorker' ORDER BY id"
               )

      assert {:ok, ^epoch} = Dawarich.Redis.cache_command(["GET", key])
      assert [[count]] == rows("SELECT count(*) FROM points")
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    end

    assert [] == File.ls!(dir)
  end

  @tag a12f3a_e11: true
  test "E11: restore worker and post-commit follow-up matches current Rails contract without a native-owner Rails effect",
       %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("version3", ScratchRepo)
    {job, context} = import_job(c, dir)
    expected = c.expected["job"]

    assert_raise RuntimeError, expected["error"]["message"], fn ->
      ImportWorker.run(ScratchRepo, job, context: context)
    end

    assert rows("SELECT title,content FROM notifications ORDER BY id") ==
             Enum.map(expected["notifications"], &[&1["title"], &1["content"]])

    before = rows("SELECT title,content FROM notifications ORDER BY id")
    assert :ok == ImportWorker.run(ScratchRepo, job, context: context)
    assert before == rows("SELECT title,content FROM notifications ORDER BY id")
    assert Processed.done?(ScratchRepo, job.args["event_id"])
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    assert [] == File.ls!(dir)
  end

  defp clean do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places,areas,tags,taggings,visits,tracks,track_segments,digests,points_raw_data_archives CASCADE"
    )
  end

  defp zip_entries(path) do
    {:ok, entries} = :zip.unzip(String.to_charlist(path), [:memory])
    Map.new(entries, fn {name, bytes} -> {List.to_string(name), bytes} end)
  end

  defp capture(number),
    do:
      File.read!(
        "test/fixtures/user_data/a12f3a-e#{String.pad_leading(to_string(number), 2, "0")}.json"
      )
      |> Jason.decode!()

  defp export_context(c) do
    secret =
      File.read!("test/fixtures/rails_cookies.json")
      |> Jason.decode!()
      |> Map.fetch!("rails_test_secret")

    c.context
    |> Map.put(:archive_key, Dawarich.RawData.ArchiveFormat.key(%{}, secret))
    |> Map.put(:application_zone, "Europe/Berlin")
  end

  defp export_args(c),
    do: %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => c.user_id,
      "time_zone" => "UTC",
      "locale" => "en"
    }

  defp import_job(c, dir) do
    blob =
      Dawarich.RailsBlobFixture.create!(
        ScratchRepo,
        c.context.storage.root,
        "backup.zip",
        File.read!(c.archive_path)
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'backup.zip',8,1,now(),now()) RETURNING id",
        [c.user_id]
      )

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
      [id, blob.id]
    )

    args = Map.merge(export_args(c), %{"import_id" => id})

    {1, [%{id: job_id}]} =
      ScratchRepo.insert_all(
        "oban_jobs",
        [
          %{
            state: "executing",
            queue: "imports",
            worker: "Dawarich.UserData.ImportWorker",
            args: args,
            attempt: 1,
            max_attempts: 1
          }
        ],
        prefix: "oban",
        returning: [:id]
      )

    Ownership.put!(ScratchRepo, "command:users.import_data", :oban)
    {%Oban.Job{id: job_id, args: args, attempt: 1}, Map.put(c.context, :temp_dir, dir)}
  end
end
