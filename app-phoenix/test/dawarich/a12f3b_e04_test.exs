defmodule Dawarich.A12f3bE04Test do
  use Dawarich.IngestCase, async: false
  import Dawarich.DataCase, only: [rows: 1, rows: 2]
  alias Dawarich.Auth.AccountDestroy
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Users.{DestroyWorker, DestructionWebhookWorker}

  setup do
    Ecto.Migrator.run(Repo, Path.expand("../../priv/repo/oban_migrations", __DIR__), :up,
      all: true,
      prefix: "oban",
      log: false
    )

    Dawarich.MigrationModules.purge()
    Dawarich.JobsCase.reset!(Repo)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    :ok
  end

  @tag a12f3b_case: "E04a"
  test "account deletion producer reaches native dependent cleanup and webhook" do
    id = user!(%{provider: "oidc"})
    other = user!()
    [[email]] = rows("SELECT email FROM users WHERE id=$1", [id])
    event = Ecto.UUID.generate()

    context = %{
      repo: Repo,
      self_hosted: true,
      enqueue_destroy: &DestroyWorker.enqueue(Repo, &1, event)
    }

    assert {:error, :transaction_required} = DestroyWorker.enqueue(Repo, id, event)

    assert {:error, :worker_owner} =
             AccountDestroy.request(id, %{"confirm_email" => email}, context)

    assert rows("SELECT deleted_at FROM users WHERE id=$1", [id]) == [[nil]]
    Ownership.put!(Repo, "command:users.destroy", :oban)
    assert {:ok, :scheduled} = AccountDestroy.request(id, %{"confirm_email" => email}, context)
    assert [[deleted]] = rows("SELECT deleted_at FROM users WHERE id=$1", [id])
    assert deleted != nil

    assert rows("SELECT command_type,payload FROM job_outbox WHERE event_id=$1", [
             Ecto.UUID.dump!(event)
           ]) ==
             [["users.destroy", %{"user_id" => id}]]

    import = insert!("imports", %{user_id: id, name: "owned"})
    foreign_import = insert!("imports", %{user_id: other, name: "foreign"})
    blob = blob!("owned")
    shared = blob!("shared")
    attach!("Import", import, blob)
    attach!("Import", import, shared)
    attach!("Import", foreign_import, shared)

    place =
      insert!("places", %{
        user_id: id,
        name: "owned",
        latitude: Decimal.new(0),
        longitude: Decimal.new(0)
      })

    foreign_visit =
      insert!("visits", %{
        user_id: other,
        place_id: place,
        name: "foreign",
        duration: 1,
        started_at: ~N[2026-01-01 00:00:00],
        ended_at: ~N[2026-01-02 00:00:00]
      })

    trip =
      insert!("trips", %{
        user_id: id,
        name: "owned",
        started_at: ~N[2026-01-01 00:00:00],
        ended_at: ~N[2026-01-02 00:00:00]
      })

    day = insert!("planned_days", %{trip_id: trip, date: ~D[2026-01-01], position: 0})
    note = insert!("planned_day_notes", %{planned_day_id: day, body: "owned", position: 0})
    point = point!(id, %{import_id: import})

    invitation =
      insert!("family_invitations", %{
        family_id: family!(other),
        invited_by_id: id,
        email: "invite@example.invalid",
        token: "synthetic",
        expires_at: ~N[2026-12-01 00:00:00]
      })

    keys =
      for suffix <- ~w(countries_visited cities_visited total_distance years_tracked),
          do: "dawarich/user_#{id}_#{suffix}"

    keys = keys ++ Enum.map(keys, &("phoenix/" <> &1))

    for key <- keys,
        do: assert({:ok, "OK"} = Dawarich.Redis.cache_command(["SET", key, "synthetic"]))

    for {type, user} <- [
          {"mail.user.welcome", id},
          {"mail.user.welcome", other},
          {"unknown.accepted", id}
        ] do
      rows(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),$1,1,'{}',$2,now())",
        [type, user]
      )
    end

    args = %{"user_id" => id, "event_id" => event}
    assert DestroyWorker.args_from_command(1, %{"user_id" => id}) == {:ok, %{"user_id" => id}}

    assert DestroyWorker.args_from_command(1, %{"user_id" => "bad"}) ==
             {:error, "invalid_payload"}

    assert DestroyWorker.args_from_command(2, %{}) == {:error, "unsupported_version"}
    assert DestroyWorker.new(args).changes.max_attempts == 4
    Ownership.put!(Repo, "command:users.destroy", :sidekiq, pinned: true)
    Ownership.put!(Repo, "command:users.destruction_webhook", :sidekiq, pinned: true)
    assert :ok = DestroyWorker.run(Repo, args)
    assert :ok = DestroyWorker.run(Repo, args)
    assert Processed.done?(Repo, event)
    assert {:ok, values} = Dawarich.Redis.cache_command(["MGET" | keys])
    assert Enum.all?(values, &(&1 == "synthetic"))

    assert [[cache]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.AfterCommit.Worker'")

    assert cache["operation"] == "keys"
    assert cache["payload"]["keys"] == keys

    assert rows("SELECT aggregate_id FROM job_outbox WHERE command_type='mail.user.welcome'") == [
             [other]
           ]

    assert rows("SELECT aggregate_id FROM job_outbox WHERE command_type='unknown.accepted'") == [
             [id]
           ]

    for {table, record} <- [
          {"users", id},
          {"points", point},
          {"imports", import},
          {"places", place},
          {"trips", trip},
          {"planned_days", day},
          {"planned_day_notes", note},
          {"family_invitations", invitation}
        ] do
      assert rows("SELECT id FROM #{table} WHERE id=$1", [record]) == []
    end

    assert rows("SELECT place_id FROM visits WHERE id=$1", [foreign_visit]) == [[nil]]
    assert rows("SELECT id FROM imports WHERE id=$1", [foreign_import]) == [[foreign_import]]
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared]) == [[shared]]
    assert [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob])
    assert Jason.decode!(metadata)["phoenix_purge_pending"] == true

    assert [[%{"objects" => [%{"key" => "owned", "service_name" => "test"}]} = purge]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'")

    root =
      Path.join(Application.fetch_env!(:dawarich, :test_tmp_dir), "e04-" <> Ecto.UUID.generate())

    on_exit(fn -> File.rm_rf!(root) end)
    services = %{services: %{"test" => %{service: "local", root: root}}}

    for key <- ["owned", "shared"] do
      path = Dawarich.Storage.disk_path(root, key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "synthetic")
    end

    assert :ok = Dawarich.Exports.PurgeWorker.run(purge, services: services, repo: Repo)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []
    refute File.exists?(Dawarich.Storage.disk_path(root, "owned"))
    assert File.exists?(Dawarich.Storage.disk_path(root, "shared"))

    assert [[snapshot]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestructionWebhookWorker'"
             )

    assert snapshot["user_id"] == id
    assert snapshot["email"] == email
    parent = self()

    assert :ok =
             DestructionWebhookWorker.run(Repo, snapshot,
               env: %{
                 "MANAGER_URL" => "https://manager.example.invalid",
                 "JWT_SECRET_KEY" => "synthetic-e04"
               },
               http: fn _, _, body, _ ->
                 send(parent, {:webhook, body})
                 {:ok, 200, ""}
               end
             )

    assert_receive {:webhook, body}
    [_, payload, _] = String.split(Jason.decode!(body)["token"], ".")
    assert Jason.decode!(Base.url_decode64!(payload, padding: false))["email"] == email
    assert commands() == []
    live = user!()
    assert :ok = DestroyWorker.run(Repo, %{"user_id" => live, "event_id" => Ecto.UUID.generate()})
    assert rows("SELECT id FROM users WHERE id=$1", [live]) == [[live]]
    blocked = user!(%{deleted_at: NaiveDateTime.utc_now()})
    family = family!(blocked)
    insert!("family_memberships", %{user_id: blocked, family_id: family, role: 0})
    insert!("family_memberships", %{user_id: other, family_id: family, role: 1})

    assert {:cancel, "account deletion blocked by family members"} =
             DestroyWorker.run(Repo, %{"user_id" => blocked, "event_id" => Ecto.UUID.generate()})

    assert rows("SELECT id FROM users WHERE id=$1", [blocked]) == [[blocked]]
  end

  @tag a12f3b_case: "E04b"
  test "account deletion failed child effect remains retryable without source replay" do
    id = user!(%{deleted_at: NaiveDateTime.utc_now()})
    other = user!()

    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,now(),now(),ST_GeomFromText('LINESTRING(0 0,1 1)',4326),now(),now()) RETURNING id",
        [id]
      )

    point = point!(id)
    foreign = point!(other, %{track_id: track})
    args = %{"user_id" => id, "event_id" => Ecto.UUID.generate()}
    assert {:error, {:cleanup, :foreign_key_violation}} = DestroyWorker.run(Repo, args)
    refute Processed.done?(Repo, args["event_id"])
    assert rows("SELECT id FROM points WHERE id=$1", [point]) == [[point]]
    assert rows("SELECT id FROM users WHERE id=$1", [id]) == [[id]]
    assert rows("SELECT args FROM oban.oban_jobs") == []
    assert commands() == []
    rows("UPDATE points SET track_id=NULL WHERE id=$1", [foreign])
    assert :ok = DestroyWorker.run(Repo, args)
    assert :ok = DestroyWorker.run(Repo, args)
    assert Processed.done?(Repo, args["event_id"])

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestructionWebhookWorker'"
           ) == [[1]]

    assert rows("SELECT id FROM points WHERE id=$1", [foreign]) == [[foreign]]
    assert commands() == []
    import = insert!("imports", %{user_id: other, name: "purge"})
    blob = blob!("retry-storage-key")
    attach!("Import", import, blob)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [other])

    assert :ok =
             DestroyWorker.run(Repo, %{"user_id" => other, "event_id" => Ecto.UUID.generate()})

    assert [[purge]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'")

    root =
      Path.join(Application.fetch_env!(:dawarich, :test_tmp_dir), "e04-#{Ecto.UUID.generate()}")

    on_exit(fn -> File.rm_rf!(root) end)
    services = %{services: %{"test" => %{service: "local", root: root}}}
    path = Dawarich.Storage.disk_path(root, "retry-storage-key")
    File.mkdir_p!(path)

    assert {:error, {:storage_delete, :eperm}} =
             Dawarich.Exports.PurgeWorker.run(purge, services: services, repo: Repo)

    assert rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'") ==
             [[purge]]

    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == [[blob]]
    File.rmdir!(path)
    File.write!(path, "synthetic")
    assert :ok = Dawarich.Exports.PurgeWorker.run(purge, services: services, repo: Repo)
    refute File.exists?(path)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []
    assert commands() == []
  end

  defp insert!(table, attrs) do
    stamp = NaiveDateTime.utc_now()
    row = Map.merge(%{created_at: stamp, updated_at: stamp}, attrs)
    {1, [%{id: id}]} = Dawarich.Test.SeedIds.insert_all!(Repo, table, [row], returning: [:id])
    id
  end

  defp point!(id, attrs \\ %{}) do
    [[point]] =
      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,import_id,track_id,created_at,updated_at) VALUES($1,1,ST_GeomFromText('POINT(0 0)',4326),$2,$3,now(),now()) RETURNING id",
        [id, attrs[:import_id], attrs[:track_id]]
      )

    point
  end

  defp family!(id), do: insert!("families", %{creator_id: id, name: "synthetic"})

  defp blob!(key) do
    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,service_name,byte_size,created_at) VALUES($1,'synthetic','test',0,now()) RETURNING id",
        [key]
      )

    id
  end

  defp attach!(type, record, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file',$1,$2,$3,now())",
        [type, record, blob]
      )
end
