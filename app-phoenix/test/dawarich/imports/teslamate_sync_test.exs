defmodule Dawarich.Imports.TeslamateSyncTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.Imports.Teslamate.{Sync, SyncWorker, ScheduleWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.NormalFormats
  @now ~U[2026-01-15 23:30:00Z]
  @key "command:imports.teslamate_sync"

  setup do
    Dawarich.ApiEndpointCase.clear_transport_env()
    Ownership.put!(ScratchRepo, @key, :oban)
    :ok
  end

  test "teslamate incomplete and quota runs preserve pending cursor and prior points" do
    for name <- ~w(success duplicate incomplete quota disconnected) do
      reset!(ScratchRepo)
      Ownership.put!(ScratchRepo, @key, :oban)
      c = NormalFormats.seed!("producers/teslamate/" <> name, ScratchRepo)
      server = listen()
      on_exit(fn -> :gen_tcp.close(server.listen) end)
      url = "http://127.0.0.1:#{server.port}"
      settings!(c.user_id, if(name == "disconnected", do: "", else: url))

      if name == "quota",
        do: rows("UPDATE users SET points_count=10000000 WHERE id=$1", [c.user_id])

      task = Task.async(fn -> respond(server, c.expected["requests"]) end)
      args = args(c.user_id)
      opts = [now: @now, self_hosted?: name != "quota"]
      result = Sync.run(ScratchRepo, args, opts)

      if name == "duplicate" do
        assert {:ok, c.expected["result"]} == result
        assert {:ok, c.expected["result"]} == Sync.run(ScratchRepo, args(c.user_id), opts)
      else
        expected =
          if c.expected["error"],
            do: {:error, c.expected["error"]["message"]},
            else: {:ok, c.expected["result"]}

        assert result == expected
      end

      Task.await(task)
      [[settings]] = rows("SELECT settings FROM users WHERE id=$1", [c.user_id])

      for {key, value} <- c.expected["settings"] do
        assert settings[key] == if(value == "http://127.0.0.1:19992", do: url, else: value)
      end

      if name in ~w(incomplete quota disconnected),
        do: refute(Map.has_key?(settings, "teslamate_last_synced_at"))

      captured = c.expected["points"]

      actual =
        rows(
          "SELECT ST_AsText(lonlat::geometry),timestamp,altitude,altitude_decimal,battery,velocity,tracker_id,external_track_id,raw_data FROM points WHERE user_id=$1 ORDER BY timestamp",
          [c.user_id]
        )

      assert actual ==
               Enum.map(captured, fn p ->
                 [
                   p["lonlat"],
                   p["timestamp"],
                   p["altitude"],
                   Decimal.new(p["altitude_decimal"]),
                   p["battery"],
                   p["velocity"],
                   p["tracker_id"],
                   "teslamate-drive-11",
                   p["raw_data"]
                 ]
               end)

      if captured != [] do
        assert rows("SELECT points_count FROM users WHERE id=$1", [c.user_id]) == [[1]]

        assert rows("SELECT kind FROM phoenix.rails_commands ORDER BY id") ==
                 [
                   ["points.tile_epoch"],
                   ["points.anomaly_filter"],
                   ["tracks.realtime"],
                   ["tracks.backfill"],
                   ["stats.calculate_month"]
                 ] ++ if(name == "duplicate", do: [["points.tile_epoch"]], else: [])

        assert rows(
                 "SELECT payload FROM phoenix.rails_commands WHERE kind='stats.calculate_month'"
               ) == [
                 [
                   %{
                     "user_id" => c.user_id,
                     "year" => 2026,
                     "month" => 1,
                     "notify_on_failure" => true,
                     "run_at" => DateTime.to_unix(@now)
                   }
                 ]
               ]
      else
        assert rows("SELECT kind FROM phoenix.rails_commands") == []
      end
    end

    partial_failures!()
    quota_and_recovery!()
    pagination!()
  end

  test "teslamate live lease excludes concurrent schedulers and honors entitlements" do
    c = NormalFormats.seed!("producers/teslamate/success", ScratchRepo)
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    settings!(c.user_id, "http://127.0.0.1:#{server.port}")

    first =
      Task.async(fn ->
        SyncWorker.run(ScratchRepo, args(c.user_id), now: @now, self_hosted?: true)
      end)

    socket = accept(server)
    read_head(socket)

    assert [[1]] ==
             rows("SELECT count(*) FROM phoenix.leases WHERE name=$1 AND expires_at>now()", [
               "teslamate-sync:#{c.user_id}"
             ])

    assert :ok == SyncWorker.run(ScratchRepo, args(c.user_id), now: @now, self_hosted?: true)
    answer(socket, hd(c.expected["requests"]))
    responder = Task.async(fn -> respond(server, tl(c.expected["requests"])) end)
    assert :ok == Task.await(first)
    Task.await(responder)
    assert rows("SELECT points_count FROM users WHERE id=$1", [c.user_id]) == [[1]]

    for {plan, active, count} <- [
          {1, ~N[2026-01-01 00:00:00], 0},
          {0, ~N[2027-01-01 00:00:00], 0},
          {1, ~N[2027-01-01 00:00:00], 10_000_000}
        ] do
      rows("UPDATE users SET plan=$2,active_until=$3,points_count=$4 WHERE id=$1", [
        c.user_id,
        plan,
        active,
        count
      ])

      assert :ok == SyncWorker.run(ScratchRepo, args(c.user_id), now: @now, self_hosted?: false)
    end

    assert rows("SELECT count(*) FROM points") == [[1]]

    assert SyncWorker.args_from_command(1, %{"user_id" => c.user_id}) ==
             {:ok, %{"user_id" => c.user_id}}

    assert SyncWorker.args_from_command(1, %{"user_id" => c.user_id, "extra" => true}) ==
             {:error, "invalid_payload"}

    assert SyncWorker.args_from_command(2, %{"user_id" => c.user_id}) ==
             {:error, "unsupported_version"}

    Ownership.put!(ScratchRepo, "cron:teslamate_sync_job", :oban)
    assert :ok == ScheduleWorker.run(ScratchRepo)

    assert rows("SELECT command_type,payload FROM job_outbox") == [
             ["imports.teslamate_sync", %{"user_id" => c.user_id}]
           ]

    Ownership.put!(ScratchRepo, "cron:teslamate_sync_job", :sidekiq)
    assert :ok == ScheduleWorker.run(ScratchRepo)
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    before = rows("SELECT updated_at FROM points WHERE user_id=$1", [c.user_id])

    responder =
      Task.async(fn ->
        requests =
          List.update_at(c.expected["requests"], 1, fn r ->
            Map.put(r, "query", Map.put(r["query"], "startDate", ["2026-01-08T23:30:00Z"]))
          end)

        respond(server, Enum.take(requests, 2))
        socket = accept(server)
        read_head(socket)
        settings!(c.user_id, "")
        answer(socket, List.last(c.expected["requests"]))
      end)

    assert {:cancel, :ownership_lost} ==
             SyncWorker.run(ScratchRepo, args(c.user_id),
               now: @now,
               self_hosted?: true,
               job: %Oban.Job{attempt: 3, max_attempts: 3}
             )

    Task.await(responder)
    assert rows("SELECT updated_at FROM points WHERE user_id=$1", [c.user_id]) == before
    assert rows("SELECT count(*) FROM notifications") == [[0]]
  end

  defp partial_failures! do
    reset!(ScratchRepo)
    Ownership.put!(ScratchRepo, @key, :oban)
    c = NormalFormats.seed!("producers/teslamate/success", ScratchRepo)
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    settings!(c.user_id, "http://127.0.0.1:#{server.port}")
    [cars, page, drive] = c.expected["requests"]

    page =
      Map.put(
        page,
        "body",
        Jason.encode!(%{
          "data" => %{
            "drives" => Enum.map(11..15, &%{"drive_id" => &1}),
            "units" => %{"unit_of_length" => "mi"}
          }
        })
      )

    errors =
      Enum.map(12..14, fn id ->
        %{
          "path" => "/api/v1/cars/1/drives/#{id}",
          "query" => %{},
          "body" => ~s({"data":{"drive":{}}})
        }
      end)

    task = Task.async(fn -> respond(server, [cars, page, drive] ++ errors) end)
    args = args(c.user_id)

    assert {:error, message} =
             Sync.run(ScratchRepo, args,
               now: @now,
               self_hosted?: true,
               job: %Oban.Job{attempt: 3, max_attempts: 3}
             )

    Task.await(task)

    assert message ==
             "TeslaMateApi sync incomplete: " <>
               Enum.map_join(12..14, "; ", fn id ->
                 "car 1, drive #{id}: TeslaMateApi response did not contain drive details"
               end)

    assert rows(
             "SELECT points_count,settings->>'teslamate_processing_pending',settings->>'teslamate_last_synced_at' FROM users WHERE id=$1",
             [c.user_id]
           ) == [[1, "true", nil]]

    assert rows("SELECT kind FROM phoenix.rails_commands ORDER BY id") == [
             ["points.tile_epoch"],
             ["points.anomaly_filter"],
             ["tracks.realtime"],
             ["tracks.backfill"],
             ["stats.calculate_month"]
           ]

    assert rows("SELECT title,content,kind FROM notifications") == [
             [
               "TeslaMateApi-Synchronisation fehlgeschlagen",
               "Deine TeslaMateApi-Synchronisation ist mit folgendem Fehler fehlgeschlagen: #{message}. Prüfe deine Integrationseinstellungen und versuche es erneut.",
               2
             ]
           ]
  end

  defp quota_and_recovery! do
    reset!(ScratchRepo)
    Ownership.put!(ScratchRepo, @key, :oban)
    c = NormalFormats.seed!("producers/teslamate/success", ScratchRepo)
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    settings!(c.user_id, "http://127.0.0.1:#{server.port}")
    rows("UPDATE users SET points_count=9999999 WHERE id=$1", [c.user_id])
    [cars, page, drive] = c.expected["requests"]
    payload = Jason.decode!(drive["body"])
    detail = hd(payload["data"]["drive"]["drive_details"])
    second = Map.merge(detail, %{"date" => "2026-01-15T23:31:00Z", "detail_id" => 113})
    third = Map.merge(detail, %{"date" => "2026-01-15T23:32:00Z", "detail_id" => 114})

    drive =
      Map.put(
        drive,
        "body",
        Jason.encode!(
          put_in(payload, ["data", "drive", "drive_details"], [detail, detail, second, third])
        )
      )

    task = Task.async(fn -> respond(server, [cars, page, drive]) end)

    assert {:ok, %{"cars" => 1, "drives" => 1, "points" => 2, "skipped_points" => 2}} ==
             Sync.run(ScratchRepo, args(c.user_id), now: @now, self_hosted?: false)

    Task.await(task)

    assert rows(
             "SELECT points_count,settings->>'teslamate_last_synced_at',settings->>'teslamate_processing_pending' FROM users WHERE id=$1",
             [c.user_id]
           ) == [[10_000_000, nil, "false"]]

    assert rows("SELECT count(*) FROM points") == [[1]]
    rows("DELETE FROM phoenix.rails_commands")

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      c.user_id,
      %{
        "teslamate_processing_pending" => true,
        "teslamate_processing_pending_url" => "http://127.0.0.1:#{server.port}"
      }
    ])

    task = Task.async(fn -> respond(server, c.expected["requests"]) end)

    assert {:ok, c.expected["result"]} ==
             Sync.run(ScratchRepo, args(c.user_id), now: @now, self_hosted?: true)

    Task.await(task)

    assert rows("SELECT kind FROM phoenix.rails_commands ORDER BY id") == [
             ["points.tile_epoch"],
             ["points.anomaly_filter"],
             ["tracks.realtime"],
             ["tracks.backfill"],
             ["stats.calculate_month"]
           ]

    assert rows("SELECT count(*) FROM points") == [[1]]
  end

  defp pagination! do
    reset!(ScratchRepo)
    Ownership.put!(ScratchRepo, @key, :oban)
    c = NormalFormats.seed!("producers/teslamate/success", ScratchRepo)
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    settings!(c.user_id, "http://127.0.0.1:#{server.port}")
    [cars, page, _] = c.expected["requests"]

    page =
      Map.put(
        page,
        "body",
        Jason.encode!(%{"data" => %{"drives" => Enum.map(1..100, &%{"drive_id" => &1})}})
      )

    drives =
      Enum.map(1..100, fn id ->
        %{
          "path" => "/api/v1/cars/1/drives/#{id}",
          "query" => %{},
          "body" => ~s({"data":{"drive":{"drive_details":null}}})
        }
      end)

    last = %{
      page
      | "query" => Map.put(page["query"], "page", ["2"]),
        "body" => ~s({"data":{"drives":null}})
    }

    task = Task.async(fn -> respond(server, [cars, page] ++ drives ++ [last]) end)

    assert {:ok, %{"cars" => 1, "drives" => 100, "points" => 0, "skipped_points" => 0}} ==
             Sync.run(ScratchRepo, args(c.user_id), now: @now, self_hosted?: true)

    Task.await(task)
  end

  defp args(user), do: %{"user_id" => user, "event_id" => Ecto.UUID.generate()}

  defp settings!(user, url),
    do:
      rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
        user,
        %{"teslamate_url" => url}
      ])

  defp respond(server, requests) do
    Enum.each(requests, fn expected ->
      socket = accept(server)
      {head, _} = read_head(socket)
      ["GET", path, _] = String.split(request_line(head))
      uri = URI.parse("http://127.0.0.1" <> path)
      assert uri.path == expected["path"]

      assert URI.decode_query(uri.query || "") |> Map.new(fn {k, v} -> {k, [v]} end) ==
               expected["query"]

      answer(socket, expected)
    end)
  end

  defp answer(socket, expected) do
    body = expected["body"]

    reply(
      socket,
      "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <> body
    )

    :gen_tcp.close(socket)
  end
end
