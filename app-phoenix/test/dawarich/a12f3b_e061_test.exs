defmodule Dawarich.A12f3bE061Test do
  use Dawarich.JobsCase
  import Dawarich.Test.RawHTTP
  alias Dawarich.AirTrail.{ImportFlightsWorker, SyncSchedulingWorker}
  alias Dawarich.Imports.{IntegrationCommands, Teslamate}
  alias Dawarich.Immich.VerifyWorker
  alias Dawarich.Integrations.{SyncScheduling, TeslaMateSchedulingWorker}
  alias Dawarich.Jobs.{Drain, Ownership, Processed}

  @oban __MODULE__.Oban
  @slot 1_768_519_800

  setup do
    start_oban(@oban)
    saved = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if saved, do: System.put_env("SELF_HOSTED", saved), else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  @tag a12f3b_case: "E061a"
  test "E061 native source shapes reach their terminal effects" do
    air =
      Dawarich.AirTrailStub.start(
        self(),
        200,
        Jason.encode!(%{"success" => true, "flights" => []})
      )

    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    user =
      user!(%{
        "airtrail_url" => air,
        "airtrail_api_key" => "synthetic",
        "timezone" => "Berlin",
        "teslamate_url" => "http://127.0.0.1:#{server.port}",
        "locale" => "de"
      })

    for kind <-
          ~w(imports.airtrail_flights imports.teslamate_sync imports.immich_geodata imports.photoprism_geodata geocoding.reverse_point),
        do: Ownership.put!(ScratchRepo, "command:" <> kind, :oban)

    for name <-
          ~w(start_immich_import start_photoprism_import start_airtrail_import start_teslamate_sync),
        do:
          assert(
            ScratchRepo.transaction(fn ->
              IntegrationCommands.enqueue(ScratchRepo, user, name)
            end) == {:ok, {:ok, :queued}}
          )

    for name <- ~w(start_reverse_geocoding continue_reverse_geocoding),
        do:
          assert(
            apply(IntegrationCommands, :enqueue, [ScratchRepo, user, name, [oban: @oban]]) ==
              {:ok, :queued}
          )

    assert rows("SELECT command_type,payload FROM job_outbox ORDER BY command_type") == [
             ["imports.airtrail_flights", %{"user_id" => user}],
             ["imports.immich_geodata", %{"user_id" => user, "time_zone" => "Europe/Berlin"}],
             ["imports.photoprism_geodata", %{"user_id" => user, "time_zone" => "Europe/Berlin"}],
             ["imports.teslamate_sync", %{"user_id" => user}]
           ]

    rows("DELETE FROM job_outbox")
    rows("DELETE FROM oban.oban_jobs")

    for kind <- [:airtrail, :teslamate],
        do: Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :oban)

    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    assert SyncSchedulingWorker.slot(%Oban.Job{inserted_at: ~U[2026-01-15 23:30:47Z]}) == @slot
    assert SyncSchedulingWorker.run(ScratchRepo, @oban, @slot) == :ok
    assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, @slot) == :ok
    assert SyncSchedulingWorker.run(ScratchRepo, @oban, @slot) == :ok
    assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, @slot) == :ok

    assert rows("SELECT worker,args FROM oban.oban_jobs ORDER BY id") == [
             [
               inspect(ImportFlightsWorker),
               %{"user_id" => user, "event_id" => SyncScheduling.event_id(:airtrail, @slot, user)}
             ],
             [
               inspect(Teslamate.SyncWorker),
               %{
                 "user_id" => user,
                 "event_id" => SyncScheduling.event_id(:teslamate, @slot, user)
               }
             ]
           ]

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :imports, with_limit: 1)
    assert_received {:airtrail_request, "/api/flight/list", "scope=mine", ["Bearer synthetic"]}
    air_event = SyncScheduling.event_id(:airtrail, @slot, user)
    assert Processed.done?(ScratchRepo, air_event)

    assert ImportFlightsWorker.perform(%Oban.Job{
             args: %{"user_id" => user, "event_id" => air_event}
           }) == :ok

    refute_received {:airtrail_request, _, _, _}

    assert {:ok, %{"user_id" => ^user}} =
             Teslamate.SyncWorker.args_from_command(1, %{"user_id" => user})

    assert TeslaMateSchedulingWorker.new(%{}).changes.max_attempts == 26
    assert Teslamate.SyncWorker.new(%{}).changes.max_attempts == 3

    responder =
      Task.async(fn ->
        socket = accept(server)
        {head, _} = read_head(socket)
        assert request_line(head) == "GET /api/v1/cars HTTP/1.1"
        body = ~s({"data":{"cars":[]}})

        reply(
          socket,
          "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <>
            body
        )

        :gen_tcp.close(socket)
      end)

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :imports)
    Task.await(responder)
    assert Processed.done?(ScratchRepo, SyncScheduling.event_id(:teslamate, @slot, user))

    assert [[air_at, tesla_at]] =
             rows(
               "SELECT settings->>'airtrail_last_synced_at',settings->>'teslamate_last_synced_at' FROM users WHERE id=$1",
               [user]
             )

    assert is_binary(air_at) and is_binary(tesla_at)
    rows("DELETE FROM oban.oban_jobs")
    notification = Dawarich.Notifications.create!(ScratchRepo, user, :info, "Checking", "Pending")

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user,
      %{"immich_url" => "http://immich.test", "immich_api_key" => "synthetic"}
    ])

    args = %{
      "notification_id" => notification,
      "assets" => [%{"immich_asset_id" => "one", "latitude" => 0, "longitude" => 0}],
      "immich_url" => "http://immich.test",
      "event_id" => Ecto.UUID.generate()
    }

    assert apply(VerifyWorker, :run, [
             ScratchRepo,
             @oban,
             args,
             [
               http: fn :get, _, _, nil, _ ->
                 {:ok, 200, [], ~s({"exifInfo":{"latitude":0,"longitude":0}})}
               end
             ]
           ]) == :ok

    assert rows("SELECT kind FROM notifications WHERE id=$1", [notification]) == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  @tag a12f3b_case: "E061b"
  test "E061 accepted children prevent premature completion" do
    user = user!(%{"teslamate_url" => "http://unused.test"})
    Ownership.put!(ScratchRepo, SyncScheduling.key(:teslamate), :oban)
    Ownership.put!(ScratchRepo, "command:imports.teslamate_sync", :oban)
    assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, @slot) == :ok
    event = SyncScheduling.event_id(:teslamate, @slot, user)
    assert Processed.done?(ScratchRepo, SyncScheduling.receipt_id(:teslamate, @slot, user))
    hold_lease!(ScratchRepo, "teslamate-sync:#{user}", "source-holder")

    assert {%{success: 0, snoozed: 1, failure: 0}, snoozed_at} =
             Dawarich.Test.SnoozeClock.drain_queue(@oban, queue: :imports)

    assert [[id, %{"event_id" => ^event}, "scheduled", at, attempted]] =
             rows("SELECT id,args,state,scheduled_at,attempted_at FROM oban.oban_jobs")

    assert NaiveDateTime.diff(DateTime.to_naive(snoozed_at), attempted) >= 1
    assert at == DateTime.to_naive(DateTime.add(snoozed_at, 60, :second))
    refute Processed.done?(ScratchRepo, event)
    status = Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == 1
    assert status.shutdown == "BLOCKED"
    assert "incomplete_oban" in status.shutdown_reasons

    rows("DELETE FROM phoenix.leases WHERE name=$1 AND holder='source-holder'", [
      "teslamate-sync:#{user}"
    ])

    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user,
      %{"teslamate_url" => "http://127.0.0.1:#{server.port}"}
    ])

    responder =
      Task.async(fn ->
        socket = accept(server)
        {head, _} = read_head(socket)
        assert request_line(head) == "GET /api/v1/cars HTTP/1.1"
        body = ~s({"data":{"cars":[]}})

        reply(
          socket,
          "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <>
            body
        )

        :gen_tcp.close(socket)
      end)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(@oban, queue: :imports, with_scheduled: true)

    Task.await(responder)
    assert Processed.done?(ScratchRepo, event)

    assert rows("SELECT id,args->>'event_id',state FROM oban.oban_jobs") == [
             [id, event, "completed"]
           ]

    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    rows("DELETE FROM oban.oban_jobs")
    url = Dawarich.Test.ImmichEnrichmentStub.start(self(), ["saved"])

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      user,
      %{"immich_url" => url, "immich_api_key" => "synthetic"}
    ])

    id = Dawarich.Notifications.create!(ScratchRepo, user, :info, "Checking", "Pending")

    assets =
      Enum.map(1..21, fn n ->
        %{
          "immich_asset_id" => if(n == 1, do: "pending", else: "saved"),
          "latitude" => 52.52,
          "longitude" => 13.405
        }
      end)

    assert :ok =
             apply(Dawarich.Immich.Enrichment, :enqueue, [
               ScratchRepo,
               @oban,
               id,
               assets,
               url,
               DateTime.utc_now()
             ])

    for pass <- 1..4 do
      assert Drain.status(ScratchRepo).counts.incomplete_oban == 1

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(@oban, queue: :default, with_scheduled: true, with_limit: 1)

      if pass < 4 do
        assert rows("SELECT title FROM notifications WHERE id=$1", [id]) == [["Checking"]]
        assert Drain.status(ScratchRepo).shutdown == "BLOCKED"
      end
    end

    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    assert [[1, content]] = rows("SELECT kind,content FROM notifications WHERE id=$1", [id])
    assert content =~ "20"
    assert content =~ "1"
    assert_received {:immich_request, "GET", "/api/assets/pending", ["synthetic"], ""}
    refute_received {:immich_request, "PUT", _, _, _}
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  defp user!(settings) do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES($1,$2,now(),now()) RETURNING id",
        ["e061-#{System.unique_integer([:positive])}@test", settings]
      )

    id
  end
end
