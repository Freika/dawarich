defmodule Dawarich.Exports.PointsTimeZoneTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Exports.PointsWorker
  alias Dawarich.Jobs.Dispatch

  @oban Dawarich.PointsTimeZoneTestOban

  setup do
    root = Path.join(System.tmp_dir!(), "points-zone-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous_root = Application.fetch_env!(:dawarich, :rails_root)
    Application.put_env(:dawarich, :rails_root, root)
    backend = System.get_env("STORAGE_BACKEND")
    zone = System.get_env("TIME_ZONE")
    System.delete_env("STORAGE_BACKEND")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, previous_root)
      File.rm_rf!(root)
      if backend, do: System.put_env("STORAGE_BACKEND", backend)
      if zone, do: System.put_env("TIME_ZONE", zone), else: System.delete_env("TIME_ZONE")
    end)

    [[user]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('zone@example.test', now(), now()) RETURNING id"
      )

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, 1774748800, ST_SetSRID(ST_MakePoint(13.4, 0.00005), 4326)::geography, now(), now())",
      [user]
    )

    [[export]] =
      rows(
        "INSERT INTO exports (name, status, file_format, file_type, start_at, end_at, user_id, created_at, updated_at) VALUES ('zone.gpx', 0, 1, 0, '2026-03-29 00:00:00', '2026-03-30 00:00:00', $1, now(), now()) RETURNING id",
        [user]
      )

    %{root: root, user: user, export: export}
  end

  for {zone, want} <- [
        {"America/New_York", "2026-03-28T21:46:40-04:00"},
        {"Eastern Time (US & Canada)", "2026-03-28T21:46:40-04:00"},
        {"UTC", "2026-03-29T01:46:40Z"},
        {"Berlin", "2026-03-29T03:46:40+02:00"},
        {"Asia/Tokyo", "2026-03-29T10:46:40+09:00"}
      ] do
    test "the downloaded GPX carries the captured #{zone} zone", ctx do
      args = %{
        "event_id" => Ecto.UUID.generate(),
        "export_id" => ctx.export,
        "user_id" => ctx.user,
        "time_zone" => unquote(zone)
      }

      rows(
        "UPDATE users SET settings = '{\"timezone\":\"Pacific/Auckland\"}'::jsonb WHERE id = $1",
        [ctx.user]
      )

      assert File.cd!(ctx.root, fn -> perform_job(PointsWorker, args) end) == :ok
      assert [[2]] = rows("SELECT status FROM exports WHERE id = $1", [ctx.export])
      [path] = Path.wildcard(Path.join(ctx.root, "storage/??/??/*"))
      assert {:ok, [{~c"zone.gpx", xml}]} = :zip.unzip(to_charlist(path), [:memory])
      assert xml =~ "<time>" <> unquote(want) <> "</time>"
    end
  end

  test "v2 dispatch persists the captured zone in the real Oban job", ctx do
    start_oban(@oban)

    payload = %{
      "export_id" => ctx.export,
      "user_id" => ctx.user,
      "time_zone" => "America/New_York"
    }

    event = outbox!(command_type: "exports.points", command_version: 2, payload: payload)

    assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 1}
    assert [[args, %{"command_version" => 2}]] = rows("SELECT args, meta FROM oban.oban_jobs")
    assert args == Map.put(payload, "event_id", event)
  end

  test "v2 decoder is strict while queued v1 payloads remain valid", ctx do
    legacy = %{"export_id" => ctx.export, "user_id" => ctx.user}
    current = Map.put(legacy, "time_zone", "America/New_York")
    assert PointsWorker.args_from_command(1, legacy) == {:ok, legacy}
    assert PointsWorker.args_from_command(2, current) == {:ok, current}

    for invalid <- [
          legacy,
          Map.put(current, "time_zone", nil),
          Map.put(current, "time_zone", ""),
          Map.put(current, "time_zone", 1),
          Map.put(current, "email", "private@example.test"),
          Map.put(current, "export_id", "1")
        ] do
      assert PointsWorker.args_from_command(2, invalid) == {:error, "invalid_payload"}
    end

    assert PointsWorker.args_from_command(1, current) == {:error, "invalid_payload"}
    assert PointsWorker.args_from_command(3, current) == {:error, "unsupported_version"}
  end
end
