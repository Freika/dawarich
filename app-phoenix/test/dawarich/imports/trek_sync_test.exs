defmodule Dawarich.Imports.TrekSyncTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.Imports.Trek.{Sync, Client}
  alias Dawarich.Test.NormalFormats
  @now ~U[2026-01-15 23:30:00Z]

  test "trek repeated normalized payload keeps user edits and avoids recalculation" do
    {c, source, server} = seed!("success")
    expected = c.expected["result"]["trips"] |> hd()
    request = hd(c.expected["requests"])
    task = Task.async(fn -> respond(server, [request, request]) end)

    assert {:ok, %{id: trip, created: true, changed: true}} =
             Sync.import(ScratchRepo, source, "selected", now: @now, self_hosted?: true)

    assert rows(
             "SELECT name,source_identifier,source_status,source_snapshot,source_digest,started_at,ended_at FROM trips WHERE id=$1",
             [trip]
           ) == [
             [
               expected["name"],
               expected["source_identifier"],
               0,
               expected["source_snapshot"],
               expected["source_digest"],
               ~N[2029-12-31 23:00:00.000000],
               ~N[2030-01-02 22:59:59.999999]
             ]
           ]

    assert rows(
             "SELECT d.date,d.position,s.name,s.latitude,s.longitude,s.position,s.duration_minutes FROM planned_days d JOIN planned_stops s ON s.planned_day_id=d.id WHERE d.trip_id=$1",
             [trip]
           ) == [
             [
               ~D[2030-01-01],
               1,
               "Synthetic stop",
               Decimal.new("51.300000"),
               Decimal.new("12.400000"),
               0,
               30
             ]
           ]

    original = rows("SELECT id FROM planned_days WHERE trip_id=$1", [trip])
    rows("UPDATE trips SET name='My own title' WHERE id=$1", [trip])

    assert {:ok, %{id: ^trip, created: false, changed: false}} =
             Sync.import(ScratchRepo, source, "selected", now: @now, self_hosted?: true)

    assert rows("SELECT name FROM trips WHERE id=$1", [trip]) == [["My own title"]]
    assert rows("SELECT id FROM planned_days WHERE trip_id=$1", [trip]) == original
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    Task.await(task)
    notes_and_calculation!(source, server, request)
    client_shapes!(source, server)
  end

  test "trek stopped archived and undated trips preserve Rails disposition" do
    {c, source, server} = seed!("stopped")
    requests = c.expected["requests"]
    task = Task.async(fn -> respond(server, requests) end)

    assert {:ok, %{id: trip}} =
             Sync.import(ScratchRepo, source, "selected", now: @now, self_hosted?: true)

    assert {:ok, result} = Sync.call(ScratchRepo, source, now: @now, self_hosted?: true)
    assert result == Map.put(c.expected["result"]["result"]["sync"], "next_cursor", trip)
    assert rows("SELECT source_status FROM trips WHERE id=$1", [trip]) == [[1]]
    assert rows("SELECT count(*) FROM planned_days WHERE trip_id=$1", [trip]) == [[1]]
    Task.await(task)

    for {body, error} <- [
          {"{}",
           "TREK trip response is invalid: trip is missing required fields: start_date, end_date"},
          {~s({"start_date":null,"end_date":null}),
           "TREK trip needs start and end dates before it can be imported"},
          {~s({"start_date":"2030-01-02","end_date":"2030-01-01"}),
           "TREK trip response is invalid: trip end_date precedes start_date"}
        ] do
      rows("UPDATE trips SET source_status=0 WHERE id=$1", [trip])

      task =
        Task.async(fn ->
          respond(server, [
            list_request(),
            %{"path" => "/api/v1/trips/selected", "body" => body, "status" => 200}
          ])
        end)

      assert {:ok, %{"stopped" => 1}} =
               Sync.call(ScratchRepo, source, now: @now, self_hosted?: true)

      assert rows("SELECT source_status FROM trips WHERE id=$1", [trip]) == [[1]]
      assert rows("SELECT last_error FROM trip_sources WHERE id=$1", [source]) == [[error]]
      Task.await(task)
    end

    rows("UPDATE trips SET source_status=0 WHERE id=$1", [trip])

    task =
      Task.async(fn ->
        respond(server, [
          list_request(),
          %{"path" => "/api/v1/trips/selected", "body" => "{}", "status" => 404}
        ])
      end)

    assert {:ok, %{"stopped" => 1}} =
             Sync.call(ScratchRepo, source, now: @now, self_hosted?: true)

    assert rows("SELECT source_status FROM trips WHERE id=$1", [trip]) == [[1]]

    assert rows("SELECT last_error FROM trip_sources WHERE id=$1", [source]) == [
             ["TREK request failed with HTTP 404"]
           ]

    Task.await(task)

    task =
      Task.async(fn ->
        respond(server, [%{"path" => "/api/v1/trips", "body" => "{}", "status" => 401}])
      end)

    assert {:error, %{__struct__: Client.Error, status: 401}} =
             Sync.call(ScratchRepo, source, now: @now, self_hosted?: true)

    assert rows("SELECT status,last_error FROM trip_sources WHERE id=$1", [source]) == [
             [1, "TREK request failed with HTTP 401"]
           ]

    Task.await(task)
  end

  defp notes_and_calculation!(source, server, request) do
    payload = Jason.decode!(request["body"])

    payload =
      payload
      |> Map.put("start_date", "2026-01-14")
      |> Map.put("end_date", "2026-01-17")
      |> Map.put("days", [
        %{
          "date" => "2026-01-14",
          "day_number" => 1,
          "notes" => "Check the rental car",
          "day_notes" => [%{"time" => "09:00", "text" => "Bring the tickets"}],
          "places" => [%{"name" => "Uffizi", "time" => "14:00", "lat" => 43.76, "lng" => 11.25}],
          "reservations" => [%{"time" => "08:00"}]
        }
      ])
      |> Map.put("accommodations", [
        %{"start_date" => "2026-01-14", "end_date" => "2026-01-15", "check_in" => "15:00"}
      ])
      |> Map.put("travellers", [%{"name" => "ada", "owner" => true}])

    post = %{"path" => "/api/v1/trips/past", "body" => Jason.encode!(payload)}
    task = Task.async(fn -> respond(server, [post, post]) end)

    assert {:ok, %{id: trip, changed: true}} =
             Sync.import(ScratchRepo, source, "past", now: @now, self_hosted?: true)

    assert rows(
             "SELECT body,noted_at FROM notes WHERE attachable_type='Trip' AND attachable_id=$1",
             [trip]
           ) == [
             ["Check the rental car\n09:00 Bring the tickets", ~N[2026-01-14 12:00:00.000000]]
           ]

    assert rows(
             "SELECT starts_at FROM planned_stops s JOIN planned_days d ON d.id=s.planned_day_id WHERE d.trip_id=$1",
             [trip]
           ) == [["14:00:00"]]

    assert rows("SELECT title,starts_at FROM planned_reservations WHERE trip_id=$1", [trip]) == [
             ["Reservation", ~N[2026-01-14 07:00:00.000000]]
           ]

    assert rows("SELECT name,check_in_at FROM planned_accommodations WHERE trip_id=$1", [trip]) ==
             [["Accommodation", "15:00:00"]]

    assert rows("SELECT command_type,payload FROM job_outbox") == [
             ["trips.calculate", %{"trip_id" => trip, "distance_unit" => "km"}]
           ]

    rows(
      "UPDATE trips SET distance=100,path=ST_GeomFromText('LINESTRING(1 1,2 2)',4326),visited_countries=$2::jsonb WHERE id=$1",
      [trip, ["Italy"]]
    )

    rows(
      "UPDATE notes SET body='My own words' WHERE attachable_type='Trip' AND attachable_id=$1",
      [trip]
    )

    assert {:ok, %{id: ^trip, changed: false}} =
             Sync.import(ScratchRepo, source, "past", now: @now, self_hosted?: true)

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    Task.await(task)
    changed = put_in(payload, ["days", Access.at(0), "notes"], "Pick up the car at nine")
    task = Task.async(fn -> respond(server, [%{post | "body" => Jason.encode!(changed)}]) end)

    assert {:ok, %{changed: true}} =
             Sync.import(ScratchRepo, source, "past", now: @now, self_hosted?: true)

    assert rows("SELECT body FROM notes WHERE attachable_type='Trip' AND attachable_id=$1", [trip]) ==
             [["My own words"]]

    Task.await(task)
    rows("DELETE FROM notes WHERE attachable_type='Trip' AND attachable_id=$1", [trip])
    changed = Map.put(changed, "title", "Tuscany, renamed")
    task = Task.async(fn -> respond(server, [%{post | "body" => Jason.encode!(changed)}]) end)

    assert {:ok, %{changed: true}} =
             Sync.import(ScratchRepo, source, "past", now: @now, self_hosted?: true)

    assert rows("SELECT body FROM notes WHERE attachable_type='Trip' AND attachable_id=$1", [trip]) ==
             []

    Task.await(task)
  end

  defp client_shapes!(source, server) do
    ctx = Sync.context(ScratchRepo, source, now: @now)
    client = Client.new(ctx, encrypted?: true, self_hosted?: true)

    for {body, message} <- [
          {"[]", "TREK response does not contain a trip list"},
          {"{}", "TREK response does not contain trips"},
          {~s({"trips":[{}]}), "TREK trip list contains an invalid trip"},
          {~s({"trips":[{"id":12},{"id":"12"}]}), "TREK trip list contains an invalid trip"},
          {"invalid-json", "TREK returned invalid JSON"}
        ] do
      task = Task.async(fn -> respond(server, [%{"path" => "/api/v1/trips", "body" => body}]) end)
      assert {:error, %{message: ^message}} = Client.trips(client)
      Task.await(task)
    end

    assert {:error, %{message: "TREK URL was rejected: URL resolves to a blocked address"}} =
             Client.trips(Client.new(ctx, encrypted?: true, self_hosted?: false))

    for {address, hosted, blocked} <- [
          {{127, 0, 0, 1}, true, false},
          {{127, 0, 0, 1}, false, true},
          {{169, 254, 169, 254}, true, true},
          {{10, 0, 0, 1}, true, false},
          {{0, 0, 0, 0, 0, 65535, 0x7F00, 1}, false, true},
          {{0, 0, 0, 0, 0, 0, 0, 1}, false, true},
          {{0xFE80, 0, 0, 0, 0, 0, 0, 1}, true, true}
        ],
        do:
          assert(
            Dawarich.Imports.Trek.Endpoint.blocked?(address, hosted) == blocked,
            inspect({address, hosted})
          )

    task =
      Task.async(fn ->
        respond(server, [%{"path" => "/api/v1/trips", "body" => "{}", "status" => 302}])
      end)

    assert {:error, %{status: 302}} = Client.trips(client)
    Task.await(task)
  end

  defp seed!(name) do
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    c = NormalFormats.seed!("producers/trek/" <> name, ScratchRepo)
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    {:ok, key} = Dawarich.ActiveRecordEncryption.key()
    encrypted = Dawarich.ActiveRecordEncryption.encrypt("synthetic-trek-key", key)

    rows(
      "INSERT INTO trip_sources(id,user_id,provider,base_url,api_key,selection_token,created_at,updated_at) VALUES(987401,$1,'trek',$2,$3,'synthetic-selection',now(),now())",
      [c.user_id, "http://127.0.0.1:#{server.port}", encrypted]
    )

    rows("SELECT setval(pg_get_serial_sequence('trips','id'),987300,true)")
    {c, 987_401, server}
  end

  defp list_request,
    do: %{"path" => "/api/v1/trips", "body" => ~s({"trips":[{"id":"selected","archived":false}]})}

  defp respond(server, requests) do
    Enum.each(requests, fn expected ->
      socket = accept(server)
      {head, _} = read_head(socket)
      assert request_line(head) == "GET #{expected["path"]} HTTP/1.1"
      assert header(head, "authorization") == ["Bearer synthetic-trek-key"]
      body = expected["body"]

      reply(
        socket,
        "HTTP/1.1 #{expected["status"] || 200} OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
          body
      )

      :gen_tcp.close(socket)
    end)
  end
end
