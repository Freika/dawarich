defmodule Dawarich.Imports.TrekWorkerTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.Imports.Trek.{ImportWorker, SyncWorker, ScheduleWorker}
  alias Dawarich.Test.NormalFormats
  alias Dawarich.Jobs.Ownership
  @now ~U[2026-01-15 23:30:00Z]

  test "trek disconnect after fetch prevents every stale trip and note write" do
    for change <- [:token, :disconnect, :owner] do
      Dawarich.JobsCase.reset!(ScratchRepo)
      {c, args, server} = seed!("success")
      task = Task.async(fn -> ImportWorker.run(ScratchRepo, args, opts()) end)
      socket = accept(server)
      {head, _} = read_head(socket)
      assert request_line(head) == "GET /api/v1/trips/selected HTTP/1.1"

      case change do
        :token ->
          rows("UPDATE trip_sources SET selection_token='newer-selection' WHERE id=$1", [
            args["source_id"]
          ])

        :disconnect ->
          rows("DELETE FROM trip_sources WHERE id=$1", [args["source_id"]])

        :owner ->
          Ownership.put!(ScratchRepo, "command:imports.trek_import", :sidekiq)
      end

      request = hd(c.expected["requests"])
      payload = Jason.decode!(request["body"])
      payload = put_in(payload, ["days", Access.at(0), "notes"], "Synthetic day note")
      send_response(socket, %{request | "body" => Jason.encode!(payload)})
      assert {:cancel, :ownership_lost} = Task.await(task)
      assert rows("SELECT count(*) FROM trips") == [[0]]
      assert rows("SELECT count(*) FROM notes") == [[0]]
      assert rows("SELECT count(*) FROM job_outbox") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end
  end

  test "trek chunk continuation and final stop set match Rails" do
    {c, args, server} = seed!("continuation")

    identifiers =
      Enum.map(c.expected["requests"], &String.replace_prefix(&1["path"], "/api/v1/trips/", ""))

    identifiers = identifiers ++ ["selected"]
    args = Map.put(args, "identifiers", identifiers)
    foreign_lease!("trek-sync:#{args["source_id"]}")

    assert :ok =
             ImportWorker.run(
               ScratchRepo,
               Map.put(args, "event_id", Ecto.UUID.generate()),
               opts()
             )

    assert rows("SELECT payload FROM job_outbox") == [[Map.drop(args, ["event_id"])]]
    end_foreign_lease!("trek-sync:#{args["source_id"]}")
    rows("DELETE FROM job_outbox")

    rows(
      "INSERT INTO trips(user_id,trip_source_id,source_identifier,source_status,name,started_at,ended_at,created_at,updated_at) VALUES($1,$2,'previous',0,'Previous',now(),now(),now(),now())",
      [c.user_id, args["source_id"]]
    )

    task = Task.async(fn -> respond(server, c.expected["requests"]) end)
    assert :ok = ImportWorker.run(ScratchRepo, args, opts())
    Task.await(task)

    assert [["imports.trek_import", continuation, scheduled]] =
             rows("SELECT command_type,payload,scheduled_at FROM job_outbox")

    assert continuation == Map.drop(Map.put(args, "offset", 100), ["event_id"])
    assert scheduled == ~U[2026-01-15 23:31:00.000000Z]
    assert rows("SELECT importing FROM trip_sources") == [[true]]
    assert rows("SELECT source_status FROM trips") == [[0]]

    success =
      Path.expand("../../fixtures/imports/formats/producers/trek/success.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    request = hd(success["requests"])

    task = Task.async(fn -> respond(server, [request]) end)

    assert :ok =
             ImportWorker.run(
               ScratchRepo,
               Map.put(continuation, "event_id", Ecto.UUID.generate()),
               opts()
             )

    Task.await(task)

    assert rows("SELECT importing,last_synced_at,last_error FROM trip_sources") == [
             [false, ~N[2026-01-15 23:30:00.000000], nil]
           ]

    assert rows("SELECT source_identifier,source_status FROM trips ORDER BY source_identifier") ==
             [["previous", 1], ["selected", 0]]

    expected = hd(success["result"]["trips"])

    assert rows(
             "SELECT name,source_digest,source_snapshot FROM trips WHERE source_identifier='selected'"
           ) == [[expected["name"], expected["source_digest"], expected["source_snapshot"]]]

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    assert :ok = ImportWorker.run(ScratchRepo, args, opts())
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]

    assert {:error, "invalid_payload"} =
             ImportWorker.args_from_command(
               1,
               Map.put(Map.drop(args, ["event_id"]), "offset", -1)
             )

    rows("DELETE FROM job_outbox")
    rows("UPDATE trips SET source_status=1 WHERE source_identifier='selected'")

    rows(
      "INSERT INTO trips(user_id,trip_source_id,source_identifier,source_status,name,started_at,ended_at,created_at,updated_at) SELECT $1,$2,'managed-'||n,0,'Managed',now(),now(),now(),now() FROM generate_series(1,101) n",
      [c.user_id, args["source_id"]]
    )

    [[cursor]] = rows("SELECT id FROM trips WHERE source_identifier='managed-100'")

    request = %{
      "path" => "/api/v1/trips",
      "body" =>
        ~s({"trips":[{"id":"unselected","start_date":"2030-01-01","end_date":"2030-01-02"}]})
    }

    task = Task.async(fn -> respond(server, [request, request]) end)

    sync = %{
      "source_id" => args["source_id"],
      "after_id" => nil,
      "event_id" => Ecto.UUID.generate()
    }

    assert :ok = SyncWorker.run(ScratchRepo, sync, opts())
    assert rows("SELECT count(*) FROM trips WHERE source_status=0") == [[1]]
    assert [["imports.trek_sync", next]] = rows("SELECT command_type,payload FROM job_outbox")
    assert next == %{"source_id" => args["source_id"], "after_id" => cursor}

    assert :ok =
             SyncWorker.run(ScratchRepo, Map.put(next, "event_id", Ecto.UUID.generate()), opts())

    Task.await(task)
    assert rows("SELECT count(*) FROM trips WHERE source_status=0") == [[0]]
    assert rows("SELECT count(*) FROM trips WHERE source_identifier='unselected'") == [[0]]
  end

  test "trek terminal errors release only the current selection" do
    {c, args, server} = seed!("unauthorized")
    task = Task.async(fn -> ImportWorker.run(ScratchRepo, args, opts()) end)
    socket = accept(server)
    read_head(socket)

    rows("UPDATE trip_sources SET selection_token='newer-selection' WHERE id=$1", [
      args["source_id"]
    ])

    send_response(socket, hd(c.expected["requests"]))
    assert {:cancel, :ownership_lost} = Task.await(task)
    assert rows("SELECT importing,status,last_error FROM trip_sources") == [[true, 0, nil]]

    current =
      Map.merge(args, %{
        "selection_token" => "newer-selection",
        "event_id" => Ecto.UUID.generate()
      })

    task = Task.async(fn -> respond(server, c.expected["requests"]) end)
    assert {:discard, %{status: 401}} = ImportWorker.run(ScratchRepo, current, opts())
    Task.await(task)

    assert rows("SELECT importing,status,last_error FROM trip_sources") == [
             [false, 1, "TREK request failed with HTTP 401"]
           ]

    rows(
      "UPDATE trip_sources SET status=0,importing=true,api_key='invalid-envelope',last_error=NULL WHERE id=$1",
      [args["source_id"]]
    )

    assert {:discard, _} =
             ImportWorker.run(
               ScratchRepo,
               Map.put(current, "event_id", Ecto.UUID.generate()),
               opts()
             )

    assert rows("SELECT importing,status FROM trip_sources") == [[false, 0]]
    rows("UPDATE trip_sources SET importing=true WHERE id=$1", [args["source_id"]])
    generic = Map.put(current, "event_id", Ecto.UUID.generate())

    assert {:cancel, :ownership_lost} =
             Dawarich.Imports.Trek.WorkerState.run(
               ScratchRepo,
               generic,
               "imports.trek_import",
               opts(),
               fn ctx ->
                 rows("UPDATE trip_sources SET selection_token='third-selection' WHERE id=$1", [
                   ctx.id
                 ])

                 Dawarich.Imports.Trek.WorkerState.fail(
                   ctx,
                   RuntimeError.exception("synthetic failure")
                 )
               end
             )

    assert rows("SELECT importing,status FROM trip_sources") == [[true, 0]]

    generic =
      Map.merge(generic, %{
        "selection_token" => "third-selection",
        "event_id" => Ecto.UUID.generate()
      })

    assert {:discard, %RuntimeError{}} =
             Dawarich.Imports.Trek.WorkerState.run(
               ScratchRepo,
               generic,
               "imports.trek_import",
               opts(),
               fn ctx ->
                 Dawarich.Imports.Trek.WorkerState.fail(
                   ctx,
                   RuntimeError.exception("synthetic failure")
                 )
               end
             )

    assert rows("SELECT importing,status FROM trip_sources") == [[false, 0]]
    {:ok, key} = Dawarich.ActiveRecordEncryption.key()
    encrypted = Dawarich.ActiveRecordEncryption.encrypt("synthetic-trek-key", key)

    rows("UPDATE trip_sources SET api_key=$2,importing=true WHERE id=$1", [
      args["source_id"],
      encrypted
    ])

    request = %{hd(c.expected["requests"]) | "status" => 429}
    task = Task.async(fn -> respond(server, [request, request]) end)
    retry_args = Map.put(generic, "event_id", Ecto.UUID.generate())

    assert {:error, %{status: 429}} =
             ImportWorker.run(
               ScratchRepo,
               retry_args,
               [job: %Oban.Job{attempt: 1, max_attempts: 5}] ++ opts()
             )

    assert rows("SELECT importing FROM trip_sources") == [[true]]

    assert {:discard, %{status: 429}} =
             ImportWorker.run(
               ScratchRepo,
               retry_args,
               [job: %Oban.Job{attempt: 5, max_attempts: 5}] ++ opts()
             )

    Task.await(task)

    assert rows("SELECT importing,last_error FROM trip_sources") == [
             [false, "TREK request failed with HTTP 429"]
           ]

    rows("UPDATE trip_sources SET importing=false WHERE id=$1", [args["source_id"]])
    Ownership.put!(ScratchRepo, "cron:trek_sync_job", :oban)
    assert :ok = ScheduleWorker.run(ScratchRepo, opts())

    assert [["imports.trek_sync", %{"source_id" => source, "after_id" => nil}]] =
             rows("SELECT command_type,payload FROM job_outbox")

    assert source == args["source_id"]
    Ownership.put!(ScratchRepo, "command:imports.trek_sync", :sidekiq)

    assert {:cancel, :ownership_lost} =
             SyncWorker.run(
               ScratchRepo,
               %{"source_id" => source, "after_id" => nil, "event_id" => Ecto.UUID.generate()},
               opts()
             )

    rows("DELETE FROM job_outbox")
    rows("UPDATE users SET plan=0 WHERE id=$1", [c.user_id])
    assert :ok = ScheduleWorker.run(ScratchRepo, now: @now, self_hosted?: false)
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    rows("UPDATE users SET plan=1,active_until=now()-interval '1 day' WHERE id=$1", [c.user_id])
    assert :ok = ScheduleWorker.run(ScratchRepo, now: @now, self_hosted?: false)
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end

  defp opts, do: [now: @now, self_hosted?: true]

  defp seed!(name) do
    for key <- [
          "command:imports.trek_import",
          "command:imports.trek_sync",
          "command:trips.calculate"
        ],
        do: Ownership.put!(ScratchRepo, key, :oban)

    c = NormalFormats.seed!("producers/trek/" <> name, ScratchRepo)
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    {:ok, key} = Dawarich.ActiveRecordEncryption.key()
    encrypted = Dawarich.ActiveRecordEncryption.encrypt("synthetic-trek-key", key)

    rows(
      "INSERT INTO trip_sources(id,user_id,provider,base_url,api_key,selection_token,importing,created_at,updated_at) VALUES(987401,$1,'trek',$2,$3,'synthetic-selection',true,now(),now())",
      [c.user_id, "http://127.0.0.1:#{server.port}", encrypted]
    )

    args = %{
      "source_id" => 987_401,
      "identifiers" => ["selected"],
      "selection_token" => "synthetic-selection",
      "offset" => 0,
      "event_id" => Ecto.UUID.generate()
    }

    {c, args, server}
  end

  defp respond(server, requests) do
    for request <- requests do
      socket = accept(server)
      {head, _} = read_head(socket)
      assert request_line(head) == "GET #{request["path"]} HTTP/1.1"
      assert header(head, "authorization") == ["Bearer synthetic-trek-key"]
      send_response(socket, request)
    end
  end

  defp send_response(socket, request) do
    body = request["body"]

    reply(
      socket,
      "HTTP/1.1 #{request["status"] || 200} OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
        body
    )

    :gen_tcp.close(socket)
  end
end
