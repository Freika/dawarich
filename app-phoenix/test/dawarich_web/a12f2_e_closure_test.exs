defmodule DawarichWeb.A12f2EClosureTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Imports.Api
  alias Dawarich.Jobs.Ownership

  setup do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "a12f2e-synthetic-checkout-not-for-production")

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    for spec <- Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        do: start_supervised!(spec)

    :ok
  end

  @tag :a12f2_e_02
  test "Import API preserves actor pagination upload type limits name uniqueness and native processing" do
    owner = user!(%{plan: 1, points_count: 0, settings: %{"timezone" => "UTC"}})
    foreign = user!()

    [[id]] =
      Repo.query!(
        "INSERT INTO imports(user_id,name,status,created_at,updated_at) VALUES($1,'foreign.json',0,now(),now()) RETURNING id",
        [foreign]
      ).rows

    assert Api.show(Repo, owner, id) == {:error, 404, %{"error" => "Record not found"}}
    ctx = context()

    user = %{
      id: owner,
      email: "a12f2e-cloud@example.invalid",
      status: 1,
      plan: 1,
      points_count: 0,
      subscription_source: 1,
      active_until: nil,
      settings: %{"timezone" => "UTC"}
    }

    assert {:ok, [], %{current_page: 1, total_pages: 0}} = Api.index(Repo, owner, %{})
    assert {:error, 422, %{"error" => missing}} = Api.create(Repo, user, %{}, ctx)
    assert missing =~ "file"
    upload = upload!("source.json", "{}")
    Ownership.put!(Repo, "command:imports.process_normal", :oban)
    assert {:ok, 201, first} = Api.create(Repo, user, %{"file" => upload}, ctx)
    assert first["source"] == nil
    assert first["status"] == "created"
    assert first["name"] == "source.json"
    assert {:ok, 201, second} = Api.create(Repo, user, %{"file" => upload}, ctx)
    assert second["name"] == "source_20261006_120000.json"

    assert {:error, 422, %{"error" => "Name has already been taken"}} =
             Api.create(Repo, user, %{"file" => upload}, ctx)

    assert {:error, 403, %{"error" => "write_api_restricted"}} =
             Api.create(Repo, %{user | plan: 0}, %{"file" => upload}, %{ctx | self_hosted?: false})

    assert {:ok, [page_record], %{current_page: 1, total_pages: 2}} =
             Api.index(Repo, owner, %{"per_page" => "1"})

    assert page_record in [first, second]
    assert_raise ArgumentError, fn -> Api.index(Repo, owner, %{"per_page" => "0"}) end
    assert {:ok, records, %{total_pages: 1}} = Api.index(Repo, owner, %{"per_page" => "-1"})
    assert length(records) == 2

    for source <- Jason.decode!(File.read!("test/fixtures/imports_exports/api_closure.json")),
        source["name"] == "pagination" and source["status"] == 500 do
      conn =
        api_conn(user, %{"per_page" => source["per_page"]}, ctx)
        |> DawarichWeb.Api.ImportsController.call(:index)

      assert conn.status == source["status"]
      assert conn.resp_body == source["body"]
    end

    assert [[2]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='imports.process_normal'"
             ).rows

    assert [["source.json", 2, "application/json"]] =
             Repo.query!(
               "SELECT b.filename,b.byte_size,b.content_type FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_type='Import' AND a.record_id=$1",
               [first["id"]]
             ).rows

    assert {:error, 422, _} =
             Api.create(Repo, user, %{"file" => %{upload | filename: "bad.exe"}}, ctx)

    assert {:error, 422, _} =
             Api.create(
               Repo,
               %{user | status: 2, subscription_source: nil},
               %{"file" => upload!("big.json", String.duplicate("x", 11 * 1024 * 1024 + 1))},
               ctx
             )
  end

  @tag :a12f2_e_03
  test "Pending intake retains Cloud only origin file quota ticket expiry storage and error outcomes" do
    alias Dawarich.PendingImports.{Intake, Quota}

    ctx =
      Map.merge(context(), %{
        origin: "https://dawarich.app",
        base_url: "https://localhost",
        zone: "Etc/UTC",
        production?: false
      })

    assert {:error, 404, nil} = Intake.create(Repo, %{}, ctx)
    ctx = %{ctx | self_hosted?: false}
    key = Quota.key(ctx.now)
    Dawarich.Redis.cache_command(["DEL", key])
    on_exit(fn -> Dawarich.Redis.cache_command(["DEL", key]) end)
    assert {:error, 403, nil} = Intake.create(Repo, %{}, %{ctx | origin: "https://evil.example"})
    assert {:error, 400, %{"error" => "Missing file"}} = Intake.create(Repo, %{}, ctx)
    file = upload!("source.json", "{}")
    params = %{"file" => file, "original_filename" => "source.json"}

    assert {:error, 422, _} =
             Intake.create(Repo, %{params | "file" => upload!("source.json", "")}, ctx)

    assert {:error, 500, _} =
             Intake.create(Repo, params, %{ctx | storage: %{service: "local", root: file.path}})

    assert {:ok, "0"} = Dawarich.Redis.cache_command(["GET", key])
    assert [[1]] = Repo.query!("SELECT count(*) FROM pending_imports").rows
    Dawarich.Redis.cache_command(["SET", key, to_string(10 * 1024 * 1024 * 1024)])
    assert {:error, 429, _} = Intake.create(Repo, params, ctx)
    assert {:ok, to_string(10 * 1024 * 1024 * 1024)} == Dawarich.Redis.cache_command(["GET", key])
    Dawarich.Redis.cache_command(["SET", key, "0"])
    assert {:ok, 201, result} = Intake.create(Repo, params, ctx)
    assert {:ok, _} = Ecto.UUID.cast(result["claim_ticket"])
    assert result["expires_at"] == "2026-10-07T12:00:00Z"

    assert result["claim_url"] ==
             "https://localhost/users/sign_up?import_ticket=#{result["claim_ticket"]}&utm_source=tool&utm_medium=save-to-account"

    assert [["source.json", "https://dawarich.app", nil]] =
             Repo.query!(
               "SELECT original_filename,origin,claimed_at FROM pending_imports WHERE claim_ticket=$1",
               [Ecto.UUID.dump!(result["claim_ticket"])]
             ).rows

    assert {:ok, "2"} = Dawarich.Redis.cache_command(["GET", key])
    assert [] == commands()
  end

  @tag :a12f2_e_04
  test "Pending ticket claims preserve expiry one actor conversion and rollback compatible native production" do
    alias Dawarich.PendingImports.Claim
    user_id = user!(%{settings: %{"timezone" => "UTC"}})
    other = user!()
    user = %{id: user_id, status: 1, subscription_source: 1, settings: %{"timezone" => "UTC"}}
    ctx = context()
    ticket = Ecto.UUID.generate()

    [[pending]] =
      Repo.query!(
        "INSERT INTO pending_imports(claim_ticket,original_filename,origin,expires_at,created_at,updated_at) VALUES($1,'pending.json','https://dawarich.app',$2,now(),now()) RETURNING id",
        [Ecto.UUID.dump!(ticket), ~N[2026-10-07 12:00:00]]
      ).rows

    blob =
      Api.attach(
        Repo,
        "PendingImport",
        pending,
        upload!("pending.json", "{}"),
        ctx,
        "application/json"
      )

    Ownership.put!(Repo, "command:imports.process_normal", :oban)
    assert %{"id" => import, "name" => "pending.json"} = Claim.claim(Repo, user, ticket, ctx)
    assert nil == Claim.claim(Repo, %{user | id: other}, ticket, ctx)
    assert nil == Claim.claim(Repo, user, ticket, ctx)

    assert [[^user_id]] =
             Repo.query!("SELECT claimed_by_user_id FROM pending_imports WHERE id=$1", [pending]).rows

    assert [[blob_id]] =
             Repo.query!(
               "SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
               [import]
             ).rows

    assert blob_id == blob.id

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='imports.process_normal'"
             ).rows

    assert nil == Claim.claim(Repo, user, "not-a-ticket", ctx)
    assert nil == Claim.claim(Repo, user, Ecto.UUID.generate(), ctx)

    Repo.query!(
      "UPDATE pending_imports SET claimed_at=NULL,claimed_by_user_id=NULL WHERE id=$1",
      [pending]
    )

    for i <- 1..4,
        do:
          Repo.query!(
            "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES($1,$2,now(),now())",
            [user_id, "trial-limit-#{i}.json"]
          )

    assert {:error, :trial_limit} =
             Claim.claim(Repo, %{user | status: 2, subscription_source: nil}, ticket, %{
               ctx
               | now: ~U[2026-10-06 12:00:01Z]
             })

    assert [[nil]] =
             Repo.query!("SELECT claimed_at FROM pending_imports WHERE id=$1", [pending]).rows

    Repo.query!("DELETE FROM imports WHERE user_id=$1 AND name LIKE 'trial-limit-%'", [user_id])

    Repo.query!(
      "UPDATE pending_imports SET claimed_at=NULL,claimed_by_user_id=NULL,expires_at=$2 WHERE id=$1",
      [pending, ~N[2026-10-05 12:00:00]]
    )

    assert nil == Claim.claim(Repo, user, ticket, ctx)
    assert [[1]] = Repo.query!("SELECT count(*) FROM imports WHERE user_id=$1", [user_id]).rows
    failed_ticket = Ecto.UUID.generate()

    [[failed_pending]] =
      Repo.query!(
        "INSERT INTO pending_imports(claim_ticket,original_filename,origin,expires_at,created_at,updated_at) VALUES($1,'callback-claim.json','https://dawarich.app',$2,now(),now()) RETURNING id",
        [Ecto.UUID.dump!(failed_ticket), ~N[2026-10-07 12:00:00]]
      ).rows

    Repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','PendingImport',$1,$2,now())",
      [failed_pending, blob.id]
    )

    Repo.query!(
      "CREATE FUNCTION a12f2e_claim_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.command_type='imports.process_normal' THEN RAISE EXCEPTION 'synthetic callback failure'; END IF; RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a12f2e_claim_fault BEFORE INSERT ON job_outbox FOR EACH ROW EXECUTE FUNCTION a12f2e_claim_fault()"
    )

    try do
      assert_raise Postgrex.Error, fn -> Claim.claim(Repo, user, failed_ticket, ctx) end

      assert [[^user_id]] =
               Repo.query!("SELECT claimed_by_user_id FROM pending_imports WHERE id=$1", [
                 failed_pending
               ]).rows

      assert [[1]] =
               Repo.query!(
                 "SELECT count(*) FROM imports WHERE user_id=$1 AND name='callback-claim.json'",
                 [user_id]
               ).rows
    after
      Repo.query!("DROP TRIGGER a12f2e_claim_fault ON job_outbox")
      Repo.query!("DROP FUNCTION a12f2e_claim_fault()")
    end
  end

  @tag :a12f2_e_05
  test "Point mutations preserve own scope Ruby strong params relocation soft delete bulk limits and callbacks" do
    alias Dawarich.Points.ApiWrites
    actor = user!(%{points_count: 2, settings: %{"timezone" => "UTC"}})
    foreign = user!(%{points_count: 1})

    user = %{
      id: actor,
      status: 1,
      plan: 1,
      active_until: nil,
      points_count: 2,
      settings: %{"timezone" => "UTC"}
    }

    ctx = context()
    own = point!(actor, 1_790_000_000)
    second = point!(actor, 1_790_000_001)
    other = point!(foreign, 1_790_000_002)

    assert {:ok, 200, %{"count" => 1}} =
             ApiWrites.bulk_destroy(Repo, user, %{"point_ids" => [own, other]}, ctx)

    assert [[^other]] = Repo.query!("SELECT id FROM points WHERE user_id=$1", [foreign]).rows
    assert [[1]] = Repo.query!("SELECT points_count FROM users WHERE id=$1", [actor]).rows

    assert {:error, 422, %{"error" => "No points selected"}} =
             ApiWrites.bulk_destroy(Repo, user, %{}, ctx)

    assert {:error, 422, %{"limit" => 5000, "requested" => 5001}} =
             ApiWrites.bulk_destroy(
               Repo,
               user,
               %{"point_ids" => List.duplicate(second, 5001)},
               ctx
             )

    assert {:error, 404, _} = ApiWrites.destroy(Repo, user, own, ctx)

    assert {:error, 404, _} =
             ApiWrites.update(
               Repo,
               user,
               other,
               %{"point" => %{"latitude" => "51", "longitude" => "14"}},
               ctx
             )

    assert {:ok, 200, point} =
             ApiWrites.update(
               Repo,
               user,
               second,
               %{"point" => %{"latitude" => "51", "longitude" => "14", "timestamp" => 1}},
               ctx
             )

    assert {:object, pairs} = point

    assert pairs |> Map.new() |> Map.take(["latitude", "longitude", "timestamp"]) == %{
             "latitude" => "51.0",
             "longitude" => "14.0",
             "timestamp" => 1_790_000_001
           }

    assert {:ok, 200, %{"message" => "Point deleted successfully"}} =
             ApiWrites.destroy(Repo, user, second, ctx)

    assert [[0]] = Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [actor]).rows
    assert Enum.any?(commands(), fn [kind, _] -> kind == "points.web_destroy_follow_up" end)
  end

  @tag :a12f2_e_06
  test "Point position API retains history scope timestamp conflicts canonical point and recalculated track" do
    alias Dawarich.Points.ApiPosition
    actor = user!(%{settings: %{"timezone" => "UTC"}})
    user = %{id: actor, status: 1, plan: 1, active_until: nil, settings: %{"timezone" => "UTC"}}
    ctx = context()

    [[track]] =
      Repo.query!(
        "INSERT INTO tracks(user_id,start_at,end_at,distance,duration,original_path,created_at,updated_at) VALUES($1,$2,$3,1,60,ST_GeomFromText('LINESTRING(13.4 52.5,13.5 52.6)',4326),now(),now()) RETURNING id",
        [actor, ~N[2026-09-28 11:00:00], ~N[2026-09-28 11:01:00]]
      ).rows

    point = point!(actor, 1_790_593_200, track)
    point!(actor, 1_790_593_260, track)

    params = %{
      "point" => %{"latitude" => "51", "longitude" => "14", "revision" => 99},
      "track_revision" => 0,
      "history_scope" => %{"start_at" => "2026-09-28T11:00Z", "end_at" => "2026-09-28T12:00Z"}
    }

    assert {:error, 409, {:object, stale}} = ApiPosition.update(Repo, user, point, params, ctx)
    assert stale |> Map.new() |> Map.fetch!("revision") == %{"point" => 0, "track" => 0}
    assert [] == commands()
    params = put_in(params, ["point", "revision"], 0)
    assert {:ok, 200, {:object, moved}} = ApiPosition.update(Repo, user, point, params, ctx)
    assert moved |> Map.new() |> Map.fetch!("revision") == %{"point" => 1, "track" => 1}

    assert [[distance, 1]] =
             Repo.query!("SELECT distance,lock_version FROM tracks WHERE id=$1", [track]).rows

    assert distance > 1000
    assert {:error, 409, _} = ApiPosition.update(Repo, user, point, params, ctx)

    assert {:error, 422, _} =
             ApiPosition.update(
               Repo,
               user,
               point,
               put_in(params, ["history_scope", "start_at"], "bad"),
               ctx
             )

    assert {:error, 422, _} =
             ApiPosition.update(Repo, user, point, put_in(params, ["point", "latitude"], 91), ctx)

    assert {:error, 404, _} = ApiPosition.update(Repo, %{user | id: user!()}, point, params, ctx)
  end

  @tag :a12f2_e_07
  test "Anomaly reapply preserves source ranges plan guards locks and one native recalculation producer" do
    alias Dawarich.Points.ApiAnomaly
    actor = user!(%{settings: %{"timezone" => "UTC"}})
    user = %{id: actor, status: 1, plan: 1, active_until: nil, settings: %{"timezone" => "UTC"}}
    ctx = context()
    key = "anomaly_backfill_pending:#{actor}"
    Dawarich.Redis.cache_command(["DEL", key])
    Ownership.put!(Repo, "command:points.anomaly_backfill", :oban)

    assert {:ok, 202,
            %{
              "message" =>
                "Re-evaluation queued. Existing anomaly flags will be cleared and recomputed."
            }} = ApiAnomaly.reapply(Repo, user, %{"start_at" => "bad"}, ctx)

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='points.anomaly_backfill'"
             ).rows

    assert [[payload]] =
             Repo.query!(
               "SELECT payload FROM job_outbox WHERE command_type='points.anomaly_backfill'"
             ).rows

    assert payload["user_id"] == actor
    assert payload["reset"] == true
    assert {:ok, _} = Dawarich.Points.AnomalyBackfillWorker.args_from_command(1, payload)

    assert {:error, 409, %{"error" => "Anomaly re-evaluation already in progress."}} =
             ApiAnomaly.reapply(Repo, user, %{}, ctx)

    assert {:ok, true} = Dawarich.RailsCache.get(key)
    assert {:error, 401, _} = ApiAnomaly.reapply(Repo, %{user | status: 0}, %{}, ctx)
    Dawarich.Redis.cache_command(["DEL", key])

    fault_actor = user!()
    fault_key = "anomaly_backfill_pending:#{fault_actor}"
    Dawarich.Redis.cache_command(["DEL", fault_key])

    Repo.query!(
      "CREATE FUNCTION a12f2e_anomaly_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.command_type='points.anomaly_backfill' THEN RAISE EXCEPTION 'synthetic producer failure'; END IF; RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a12f2e_anomaly_fault BEFORE INSERT ON job_outbox FOR EACH ROW EXECUTE FUNCTION a12f2e_anomaly_fault()"
    )

    try do
      conn =
        api_conn(%{user | id: fault_actor}, %{}, ctx)
        |> DawarichWeb.Api.AnomalyController.call(:create)

      assert conn.status == 500
      assert {:ok, true} = Dawarich.RailsCache.get(fault_key)

      source =
        File.read!("test/fixtures/a12f2e/closure.json")
        |> Jason.decode!()
        |> Enum.find(&(&1["name"] == "anomaly_producer_failure"))

      assert source["pending"] == true
      assert conn.resp_body == source["body"]
    after
      Repo.query!("DROP TRIGGER a12f2e_anomaly_fault ON job_outbox")
      Repo.query!("DROP FUNCTION a12f2e_anomaly_fault()")
      Dawarich.Redis.cache_command(["DEL", fault_key])
    end
  end

  @tag :a12f2_e_08
  test "Points Overland OwnTracks and Traccar retain every source coercion refusal friends and partial result contract" do
    alias Dawarich.Ingest.Closure
    actor = user!(%{points_count: 0, settings: %{"timezone" => "UTC"}})

    feature = %{
      "geometry" => %{"coordinates" => [13.4, 52.5]},
      "properties" => %{"timestamp" => 1_790_000_000, "device_id" => true}
    }

    assert {:ok, [prepared], nil} = Closure.prepare(:overland, %{"locations" => [feature]}, actor)
    assert prepared.values.tracker_id == "t"
    assert prepared.payload.raw_data == feature
    assert [_] = Dawarich.Ingest.Intake.write([prepared], actor)
    assert [["t"]] = Repo.query!("SELECT tracker_id FROM points WHERE user_id=$1", [actor]).rows
    cases = File.read!("test/fixtures/ingest/golden.json") |> Jason.decode!()

    cases =
      Map.get(
        cases,
        "closure_cases",
        Enum.filter(cases["cases"], &String.starts_with?(&1["name"], "closure_"))
      )

    for kase <- cases do
      action =
        cond do
          String.contains?(kase["request"]["target"], "overland") -> :overland
          String.contains?(kase["request"]["target"], "owntracks") -> :owntracks
          String.contains?(kase["request"]["target"], "traccar") -> :traccar
          true -> :points
        end

      params = Jason.decode!(kase["request"]["body"])
      result = Closure.prepare(action, params, actor)

      if kase["response"]["status"] == 500 do
        assert {:error, 500, _} = result
      else
        assert {:ok, prepared, _} = result
        expected = List.first(kase["rows"])

        if expected do
          point = List.first(prepared)
          assert point.values.tracker_id == expected["tracker_id"]
          assert point.values.altitude == expected["altitude"]
          assert point.values.timestamp == expected["timestamp"]
        end
      end
    end

    golden = File.read!("test/fixtures/ingest/golden.json") |> Jason.decode!()

    native_cases =
      Enum.filter(golden["cases"], fn kase ->
        String.starts_with?(kase["name"], ["points_", "overland_", "owntracks_", "traccar_"]) and
          kase["name"] != "points_slice2_fault" and
          String.starts_with?(kase["request"]["body"], ["{", "["])
      end)

    for kase <- golden["closure_cases"] ++ native_cases, do: native_ingest_oracle!(golden, kase)

    assert {:error, 500, _} = Closure.prepare(:points, %{}, actor)

    assert {:error, 422, _} =
             Closure.prepare(
               :points,
               %{"locations" => [put_in(feature, ["properties", "timestamp"], "2023-02-29")]},
               actor
             )

    assert {:ok, [], nil} =
             Closure.prepare(
               :owntracks,
               %{"_type" => "waypoint", "lat" => 52.5, "lon" => 13.4, "tst" => 1},
               actor
             )

    assert {:ok, [], nil} =
             Closure.prepare(
               :traccar,
               %{
                 "device_id" => "x",
                 "location" => %{
                   "timestamp" => 1_790_000_000,
                   "latitude" => 91,
                   "longitude" => 13.4
                 }
               },
               actor
             )
  end

  @tag :a12f2_e_09
  test "Ingest upload and point failures never replay accepted SQL storage cache or external effects" do
    actor = user!(%{points_count: 0, settings: %{"timezone" => "UTC"}})

    user = %{
      id: actor,
      status: 1,
      plan: 1,
      subscription_source: 1,
      active_until: nil,
      points_count: 0,
      settings: %{"timezone" => "UTC"}
    }

    ctx = Map.put(context(), :after_commit, fn -> raise "synthetic render failure" end)

    feature = %{
      "geometry" => %{"coordinates" => [13.4, 52.5]},
      "properties" => %{"timestamp" => 1_790_000_000}
    }

    conn = api_conn(user, %{"locations" => [feature]}, ctx)
    conn = DawarichWeb.Api.IngestController.call(conn, {:native, :points})
    assert conn.status == 500
    assert [[1]] = Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [actor]).rows
    Ownership.put!(Repo, "command:imports.process_normal", :oban)

    assert {:error, 500, _} =
             Api.create(Repo, user, %{"file" => upload!("accepted.json", "{}")}, ctx)

    assert [[1]] = Repo.query!("SELECT count(*) FROM imports WHERE user_id=$1", [actor]).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='imports.process_normal'"
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM active_storage_attachments WHERE record_type='Import'"
             ).rows

    [[point]] = Repo.query!("SELECT id FROM points WHERE user_id=$1", [actor]).rows

    assert {:error, 500, _} =
             Dawarich.Points.ApiWrites.update(
               Repo,
               user,
               point,
               %{"point" => %{"latitude" => "51", "longitude" => "14"}},
               ctx
             )

    assert [[14.0, 51.0]] =
             Repo.query!(
               "SELECT ST_X(lonlat::geometry),ST_Y(lonlat::geometry) FROM points WHERE id=$1",
               [point]
             ).rows

    Repo.query!(
      "CREATE FUNCTION a12f2e_callback_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.kind='achievements.check' THEN RAISE EXCEPTION 'synthetic callback failure'; END IF; RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a12f2e_callback_fault BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION a12f2e_callback_fault()"
    )

    try do
      conn =
        api_conn(user, %{"point" => %{"latitude" => "53", "longitude" => "16"}}, context())
        |> Map.put(:path_params, %{"id" => to_string(point)})
        |> DawarichWeb.Api.PointWritesController.call(:update)

      assert conn.status == 500

      assert [[16.0, 53.0]] =
               Repo.query!(
                 "SELECT ST_X(lonlat::geometry),ST_Y(lonlat::geometry) FROM points WHERE id=$1",
                 [point]
               ).rows

      source =
        File.read!("test/fixtures/a12f2e/closure.json")
        |> Jason.decode!()
        |> Enum.find(&(&1["name"] == "relocation_callback_failure"))

      assert conn.resp_body == source["body"]
    after
      Repo.query!("DROP TRIGGER a12f2e_callback_fault ON phoenix.rails_commands")
      Repo.query!("DROP FUNCTION a12f2e_callback_fault()")
    end

    delete_actor = user!(%{points_count: 1})
    doomed = point!(delete_actor, 1_790_000_010)

    Repo.query!(
      "CREATE FUNCTION a12f2e_counter_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.id=#{delete_actor} AND NEW.points_count=0 THEN RAISE EXCEPTION 'synthetic counter failure'; END IF; RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a12f2e_counter_fault BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION a12f2e_counter_fault()"
    )

    try do
      conn =
        api_conn(%{user | id: delete_actor}, %{}, context())
        |> Map.put(:path_params, %{"id" => to_string(doomed)})
        |> DawarichWeb.Api.PointWritesController.call(:destroy)

      assert conn.status == 500
      assert [[0]] = Repo.query!("SELECT count(*) FROM points WHERE id=$1", [doomed]).rows

      assert [[1]] =
               Repo.query!("SELECT points_count FROM users WHERE id=$1", [delete_actor]).rows

      source =
        File.read!("test/fixtures/a12f2e/closure.json")
        |> Jason.decode!()
        |> Enum.find(&(&1["name"] == "delete_counter_failure"))

      assert conn.resp_body == source["body"]
    after
      Repo.query!("DROP TRIGGER a12f2e_counter_fault ON users")
      Repo.query!("DROP FUNCTION a12f2e_counter_fault()")
    end

    [[revision]] = Repo.query!("SELECT lock_version FROM points WHERE id=$1", [point]).rows

    Repo.query!(
      "CREATE FUNCTION a12f2e_position_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic position write failure'; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a12f2e_position_fault BEFORE UPDATE ON points FOR EACH ROW EXECUTE FUNCTION a12f2e_position_fault()"
    )

    try do
      params = %{
        "point" => %{"latitude" => "54", "longitude" => "17", "revision" => revision},
        "history_scope" => %{"start_at" => "1", "end_at" => "2147483647"}
      }

      conn =
        api_conn(user, params, context())
        |> Map.put(:path_params, %{"point_id" => to_string(point)})
        |> DawarichWeb.Api.PointPositionsController.call(:update)

      assert conn.status == 500

      source =
        File.read!("test/fixtures/a12f2e/closure.json")
        |> Jason.decode!()
        |> Enum.find(&(&1["name"] == "position_write_failure"))

      assert conn.resp_body == source["body"]

      assert [[16.0, 53.0, ^revision]] =
               Repo.query!(
                 "SELECT ST_X(lonlat::geometry),ST_Y(lonlat::geometry),lock_version FROM points WHERE id=$1",
                 [point]
               ).rows
    after
      Repo.query!("DROP TRIGGER a12f2e_position_fault ON points")
      Repo.query!("DROP FUNCTION a12f2e_position_fault()")
    end

    upstream = Dawarich.Test.RawHTTP.listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    parent = self()

    server =
      Task.async(fn ->
        socket = Dawarich.Test.RawHTTP.accept(upstream)
        send(parent, :upstream_replayed)
        Dawarich.Test.RawHTTP.read_head(socket)
        Dawarich.Test.RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nreplay")
      end)

    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)

    try do
      Repo.query!(
        "CREATE FUNCTION a12f2e_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.timestamp=1790001001 THEN RAISE EXCEPTION 'synthetic slice fault'; END IF; RETURN NEW; END $$"
      )

      Repo.query!(
        "CREATE TRIGGER a12f2e_fault BEFORE INSERT ON points FOR EACH ROW EXECUTE FUNCTION a12f2e_fault()"
      )

      locations =
        for index <- 1..1001,
            do: put_in(feature, ["properties", "timestamp"], 1_790_000_000 + index)

      conn =
        api_conn(user, %{"locations" => locations}, Map.delete(ctx, :after_commit))
        |> DawarichWeb.Api.IngestController.call({:native, :points})

      refute_receive :upstream_replayed, 0
      assert conn.status == 500
      assert [[1001]] = Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [actor]).rows
    after
      Task.shutdown(server, :brutal_kill)
      :gen_tcp.close(upstream.listen)
    end
  end

  defp native_ingest_oracle!(golden, kase) do
    Repo.transaction(fn ->
      Dawarich.Ingest.Sources.forget()

      for table <- ~w(users families family_memberships point_sources points),
          row <- kase["setup"][table] do
        Repo.query!(
          "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1::text::json) ON CONFLICT DO NOTHING",
          [Jason.encode!(row)]
        )
      end

      for table <- ~w(users families family_memberships point_sources points),
          do:
            Repo.query!(
              "SELECT setval(pg_get_serial_sequence('#{table}','id'),GREATEST((SELECT max(id) FROM #{table}),1))"
            )

      actor = Enum.find(kase["setup"]["users"], &(&1["id"] == kase["user_id"]))

      user =
        actor
        |> Map.take(~w(id status plan points_count active_until settings subscription_source))
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)

      user = %{user | active_until: nil}
      target = kase["request"]["target"]

      action =
        cond do
          String.contains?(target, "overland") -> :overland
          String.contains?(target, "owntracks") -> :owntracks
          String.contains?(target, "traccar") -> :traccar
          true -> :points
        end

      body = kase["request"]["body"]

      conn =
        Plug.Test.conn(:post, target, body)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
        |> DawarichWeb.Api.Body.call([])

      for statement <- kase["phoenix_fault"] || [], do: Repo.query!(statement)

      result =
        api_conn(user, conn.assigns.api_params, context())
        |> DawarichWeb.Api.IngestController.call({:native, action})

      assert result.status == kase["response"]["status"], kase["name"]

      ids =
        Repo.query!("SELECT id FROM points WHERE user_id=$1 ORDER BY id", [user.id]).rows
        |> List.flatten()
        |> Kernel.--(kase["setup_point_ids"])
        |> Enum.with_index()
        |> Map.new(fn {id, i} -> {id, "new:#{i}"} end)

      normalize = fn text ->
        Regex.replace(~r/"id":(\d+)/, text, fn whole, id ->
          case ids[String.to_integer(id)] do
            nil -> whole
            token -> ~s("id":"#{token}")
          end
        end)
      end

      assert normalize.(result.resp_body) == kase["response"]["body"], kase["name"]

      if kase["rows"] do
        result = Repo.query!(golden["rows_sql"], [user.id])

        rows =
          Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
          |> Jason.encode!()
          |> normalize.()
          |> Jason.decode!()

        differences =
          Enum.zip(rows, kase["rows"])
          |> Enum.map(fn {actual, expected} ->
            for {key, value} <- actual, value != expected[key], do: {key, value, expected[key]}
          end)

        assert rows == kase["rows"], "#{kase["name"]} #{inspect(differences)}"
      end

      Repo.rollback(:oracle_done)
    end)

    Dawarich.Ingest.Sources.forget()
  end

  defp api_conn(user, params, ctx) do
    Plug.Test.conn(:post, "/api/v1/points", Jason.encode!(params))
    |> Plug.Conn.assign(:api_user, user)
    |> Plug.Conn.assign(:api_params, params)
    |> Plug.Conn.assign(:api_context, ctx)
    |> Plug.Conn.assign(:api_started, System.monotonic_time())
    |> Plug.Conn.assign(:api_vary, false)
    |> Plug.Conn.assign(:api_request_id, "a12f2e")
    |> Plug.Conn.assign(:api_tag, "a12f2e")
    |> Plug.Conn.assign(:api_headers, [])
    |> Plug.Conn.assign(:api_if_none_match, "")
  end

  defp point!(actor, timestamp, track \\ nil) do
    [[id]] =
      Repo.query!(
        "INSERT INTO points(user_id,timestamp,track_id,lonlat,created_at,updated_at) VALUES($1,$2,$3,'POINT(13.4 52.5)',now(),now()) RETURNING id",
        [actor, timestamp, track]
      ).rows

    id
  end

  defp context do
    root = Path.join(System.tmp_dir!(), "a12f2e-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{self_hosted?: true, now: ~U[2026-10-06 12:00:00Z], storage: %{service: "local", root: root}}
  end

  defp upload!(name, data) do
    path = Path.join(System.tmp_dir!(), "a12f2e-upload-#{System.unique_integer([:positive])}")
    File.write!(path, data)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: name, content_type: "application/json"}
  end
end
