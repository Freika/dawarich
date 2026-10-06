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

    assert {:ok, [^second], %{current_page: 1, total_pages: 2}} =
             Api.index(Repo, owner, %{"per_page" => "1"})

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
