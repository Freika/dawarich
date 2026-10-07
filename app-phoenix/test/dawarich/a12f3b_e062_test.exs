defmodule Dawarich.A12f3bE062Test do
  use Dawarich.JobsCase
  import Dawarich.Test.RawHTTP

  alias Dawarich.Imports.Trek.{ImportWorker, SyncWorker}
  alias Dawarich.Integrations.SyncScheduling
  alias Dawarich.Jobs.{Drain, Ownership, Processed}

  @oban __MODULE__.Oban
  @now ~U[2026-01-15 23:30:00Z]
  @slot 1_768_519_800

  setup do
    start_oban(@oban)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  @tag a12f3b_case: "E062a"
  test "E062 native source shapes reach their terminal effects" do
    {user, source, server} = source!()
    payload = %{"source_id" => source}

    assert {:ok, %{"source_id" => ^source, "after_id" => nil}} =
             SyncWorker.args_from_command(1, payload)

    for cursor <- [nil, 1] do
      explicit = Map.put(payload, "after_id", cursor)
      assert SyncWorker.args_from_command(1, explicit) == {:ok, explicit}
    end

    for invalid <- [-1, 0, "1", %{}] do
      assert SyncWorker.args_from_command(1, Map.put(payload, "after_id", invalid)) ==
               {:error, "invalid_payload"}
    end

    assert SyncWorker.args_from_command(2, payload) == {:error, "unsupported_version"}

    assert SyncWorker.args_from_command(1, Map.put(payload, "locale", "de")) ==
             {:error, "invalid_payload"}

    Ownership.put!(ScratchRepo, SyncScheduling.key(:trek), :oban)
    assert :ok = SyncScheduling.run(ScratchRepo, @oban, :trek, @slot)
    assert :ok = SyncScheduling.run(ScratchRepo, @oban, :trek, @slot)
    [[job_id, args]] = rows("SELECT id,args FROM oban.oban_jobs")

    assert args == %{
             "source_id" => source,
             "after_id" => nil,
             "event_id" => SyncScheduling.event_id(:trek, @slot, source)
           }

    assert Ecto.UUID.cast(args["event_id"]) == {:ok, args["event_id"]}

    rows(
      "INSERT INTO trips(user_id,trip_source_id,source_identifier,source_status,name,started_at,ended_at,created_at,updated_at) VALUES($1,$2,'removed',0,'Synthetic',now(),now(),now(),now())",
      [user, source]
    )

    task = Task.async(fn -> respond(server, ~s({"trips":[]})) end)
    assert :ok = SyncWorker.run(ScratchRepo, args, now: @now, self_hosted?: true)
    Task.await(task)
    assert rows("SELECT source_status FROM trips") == [[1]]
    assert [[synced, nil]] = rows("SELECT last_synced_at,last_error FROM trip_sources")
    assert NaiveDateTime.compare(synced, DateTime.to_naive(@now)) == :eq
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert :ok = SyncWorker.run(ScratchRepo, args, now: @now, self_hosted?: true)
    rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [job_id])
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]

    rows(
      "UPDATE trip_sources SET importing=true,selection_token='synthetic-selection' WHERE id=$1",
      [source]
    )

    import_args = %{
      "source_id" => source,
      "identifiers" => ["undated"],
      "selection_token" => "synthetic-selection",
      "offset" => 0
    }

    assert ImportWorker.args_from_command(1, import_args) == {:ok, import_args}

    import_task =
      Task.async(fn ->
        respond(server, ~s({"start_date":null,"end_date":null}), "/api/v1/trips/undated")
      end)

    assert :ok =
             ImportWorker.run(ScratchRepo, Map.put(import_args, "event_id", Ecto.UUID.generate()),
               now: @now,
               self_hosted?: true
             )

    Task.await(import_task)
    assert rows("SELECT importing FROM trip_sources") == [[false]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E062b"
  test "E062 accepted children prevent premature completion" do
    {_user, source, server} = source!()
    event = SyncScheduling.event_id(:trek, @slot, source)
    args = %{"source_id" => source, "after_id" => nil, "event_id" => event}
    foreign_lease!("trek-sync:#{source}")
    Ownership.put!(ScratchRepo, SyncScheduling.key(:trek), :oban)
    assert :ok = SyncScheduling.run(ScratchRepo, @oban, :trek, @slot)
    [[job_id, ^args]] = rows("SELECT id,args FROM oban.oban_jobs")
    assert Processed.done?(ScratchRepo, SyncScheduling.receipt_id(:trek, @slot, source))
    assert {:snooze, 60} = SyncWorker.run(ScratchRepo, args, self_hosted?: true)
    assert %{snoozed: 1, success: 0, failure: 0} = Oban.drain_queue(@oban, queue: :imports)

    assert [["scheduled", ^args, due]] =
             rows("SELECT state,args,scheduled_at FROM oban.oban_jobs WHERE id=$1", [
               job_id
             ])

    refute Processed.done?(ScratchRepo, event)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    assert rows("SELECT last_synced_at FROM trip_sources") == [[nil]]
    end_foreign_lease!("trek-sync:#{source}")
    task = Task.async(fn -> respond(server, ~s({"trips":[]})) end)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(@oban,
               queue: :imports,
               with_scheduled: DateTime.from_naive!(due, "Etc/UTC")
             )

    Task.await(task)
    assert Processed.done?(ScratchRepo, event)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  defp source! do
    Dawarich.ApiEndpointCase.clear_transport_env()
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    [[user]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES($1,$2,now(),now()) RETURNING id",
        [
          "e062-#{System.unique_integer([:positive])}@example.test",
          %{"timezone" => "Europe/Berlin", "locale" => "de"}
        ]
      )

    {:ok, key} = Dawarich.ActiveRecordEncryption.key()
    encrypted = Dawarich.ActiveRecordEncryption.encrypt("synthetic-trek-key", key)

    [[source]] =
      rows(
        "INSERT INTO trip_sources(user_id,provider,base_url,api_key,importing,created_at,updated_at) VALUES($1,'trek',$2,$3,false,now(),now()) RETURNING id",
        [user, "http://127.0.0.1:#{server.port}", encrypted]
      )

    for type <- ~w(imports.trek_sync imports.trek_import trips.calculate),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    {user, source, server}
  end

  defp respond(server, body, path \\ "/api/v1/trips") do
    socket = accept(server)
    {head, _} = read_head(socket)
    assert request_line(head) == "GET #{path} HTTP/1.1"
    assert header(head, "authorization") == ["Bearer synthetic-trek-key"]

    reply(
      socket,
      "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <> body
    )

    :gen_tcp.close(socket)
  end
end
