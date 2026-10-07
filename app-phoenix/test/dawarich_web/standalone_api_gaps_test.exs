defmodule DawarichWeb.StandaloneApiGapsTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.RailsUser

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    [actor, other] =
      for label <- ~w(actor other) do
        RailsUser.insert!(%{
          id: System.unique_integer([:positive]),
          email: "api-gap-#{label}-#{Ecto.UUID.generate()}@example.invalid",
          api_key: Ecto.UUID.generate(),
          settings: %{"timezone" => "UTC", "locale" => "de"}
        })
      end

    %{actor: actor, other: other}
  end

  @tag :gap_demo_create
  test "standalone demo API reports existence and creates exactly once", c do
    assert_json(request(c.actor, :get, "/api/v1/demo_data.json"), 200, %{"exists" => false})
    assert_json(request(c.actor, :post, "/api/v1/demo_data"), 201, %{"status" => "created"})
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1 AND demo", [c.actor.id]) == [[1]]
    assert [[count]] = rows("SELECT count(*) FROM points WHERE user_id=$1", [c.actor.id])
    assert count > 0
    jobs = jobs(c.actor)
    assert Enum.any?(jobs, fn [worker, _] -> worker == "Dawarich.AfterCommit.Worker" end)
    refute Enum.any?(jobs, fn [worker, _] -> worker == "Dawarich.Imports.ProcessWorker" end)
    assert_json(request(c.actor, :post, "/api/v1/demo_data.json"), 200, %{"status" => "exists"})
    assert jobs(c.actor) == jobs
    assert_json(request(c.actor, :get, "/api/v1/demo_data"), 200, %{"exists" => true})
    assert_json(request(c.other, :get, "/api/v1/demo_data"), 200, %{"exists" => false})
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag :gap_demo_destroy
  test "standalone demo API removes only its own data and reports SQL errors", c do
    assert_json(request(c.actor, :delete, "/api/v1/demo_data"), 200, %{"status" => "no_demo_data"})

    marker(c.actor)
    marker(c.other)

    assert_json(request(c.actor, :delete, "/api/v1/demo_data.json"), 200, %{
      "status" => "destroyed"
    })

    assert_json(request(c.other, :get, "/api/v1/demo_data"), 200, %{"exists" => true})

    assert_json(request(c.actor, :delete, "/api/v1/demo_data"), 200, %{"status" => "no_demo_data"})

    marker(c.actor)
    fail_sql("imports", "DELETE", "OLD.user_id", c.actor.id)
    assert_json(request(c.actor, :delete, "/api/v1/demo_data"), 422, %{"status" => "error"})
    assert_json(request(c.actor, :get, "/api/v1/demo_data"), 200, %{"exists" => true})
    fail_sql("points", "INSERT", "NEW.user_id", c.other.id)
    rows("DELETE FROM imports WHERE user_id=$1", [c.other.id])
    assert_json(request(c.other, :post, "/api/v1/demo_data"), 422, %{"status" => "error"})
    assert_json(request(c.other, :get, "/api/v1/demo_data"), 200, %{"exists" => false})
  end

  @tag :gap_digest_create
  test "standalone digest generation matches rswag year shape validation conflicts and native jobs",
       c do
    stat(c.actor, 2024)

    assert_json(
      request(c.actor, :post, "/api/v1/digests?api_key=#{c.actor.api_key}", %{"year" => 2024},
        bearer: false
      ),
      202,
      %{"message" => "Digest for 2024 is being generated"}
    )

    assert [["Dawarich.Digests.YearlyWorker", args]] = jobs(c.actor)

    assert Map.drop(args, ["event_id"]) == %{
             "user_id" => c.actor.id,
             "year" => 2024,
             "time_zone" => "Etc/UTC"
           }

    assert is_binary(args["event_id"])

    for year <- [nil, 1969, Date.utc_today().year, 2023] do
      assert_json(request(c.actor, :post, "/api/v1/digests", %{"year" => year}), 422, %{
        "error" => "Invalid year"
      })
    end

    assert_json(request(c.other, :post, "/api/v1/digests", %{"year" => 2024}), 422, %{
      "error" => "Invalid year"
    })

    digest(c.actor, 2024, 1)

    assert_json(request(c.actor, :post, "/api/v1/digests", %{"year" => "2024tail"}), 409, %{
      "error" => "Digest already exists"
    })

    assert length(jobs(c.actor)) == 1
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='digests.calculate_year'") ==
             [[0]]
  end

  @tag :gap_digest_destroy
  test "standalone digest deletion scopes yearly records and returns an empty 204", c do
    own = digest(c.actor, 2024, 1)
    monthly = digest(c.actor, 2024, 0)
    foreign = digest(c.other, 2023, 1)
    conn = request(c.actor, :delete, "/api/v1/digests/2024.json")
    assert conn.status == 204
    assert conn.resp_body == ""
    assert get_resp_header(conn, "content-type") == []
    assert rows("SELECT id FROM digests WHERE id=$1", [own]) == []

    assert rows("SELECT id FROM digests WHERE id=ANY($1) ORDER BY id", [[monthly, foreign]]) ==
             Enum.map(Enum.sort([monthly, foreign]), &[&1])

    for year <- [2024, 2023, 9999] do
      assert_json(request(c.actor, :delete, "/api/v1/digests/#{year}"), 404, %{
        "error" => "Record not found"
      })
    end
  end

  @tag :gap_area_destroy
  test "standalone area deletion scopes records removes dependents and queues each effect once",
       c do
    own = area(c.actor)
    foreign = area(c.other)
    visit = visit(c.actor, own, place(c.actor))
    point = Dawarich.Test.DemoData.real_point(c.actor.id, 1_704_067_200)
    rows("UPDATE points SET visit_id=$2 WHERE id=$1", [point, visit])

    rows(
      "INSERT INTO notes(user_id,attachable_type,attachable_id,body,created_at,updated_at) VALUES($1,'Visit',$2,'Synthetic',now(),now()),($1,'Area',$3,'Synthetic',now(),now())",
      [c.actor.id, visit, own]
    )

    assert_json(request(c.actor, :delete, "/api/v1/areas/#{foreign}"), 404, %{
      "error" => "Record not found"
    })

    assert_json(request(c.actor, :delete, "/api/v1/areas/#{own}.json"), 200, %{
      "message" => "Area was successfully deleted"
    })

    assert rows("SELECT id FROM areas WHERE id=$1", [own]) == []
    assert rows("SELECT id FROM visits WHERE id=$1", [visit]) == []
    assert rows("SELECT visit_id FROM points WHERE id=$1", [point]) == [[nil]]
    assert rows("SELECT id FROM notes WHERE user_id=$1", [c.actor.id]) == []
    assert rows("SELECT id FROM areas WHERE id=$1", [foreign]) == [[foreign]]

    assert Enum.count(jobs(c.actor), fn [worker, _] ->
             worker == "Dawarich.Places.DeleteIfOrphanWorker"
           end) == 1

    assert Enum.count(jobs(c.actor), fn [worker, _] ->
             worker == "Dawarich.Points.VisitMonthsWorker"
           end) == 1

    before = jobs(c.actor)

    assert_json(request(c.actor, :delete, "/api/v1/areas/#{own}"), 404, %{
      "error" => "Record not found"
    })

    assert jobs(c.actor) == before
  end

  @tag :gap_auth
  test "standalone missing APIs retain API key active guards and coexistence handback", c do
    routes = [
      {:get, "/api/v1/demo_data"},
      {:post, "/api/v1/demo_data"},
      {:delete, "/api/v1/demo_data"},
      {:post, "/api/v1/digests"},
      {:delete, "/api/v1/digests/2024"},
      {:delete, "/api/v1/areas/1"}
    ]

    for {method, path} <- routes do
      assert request(c.actor, method, path, %{}, bearer: false).status == 401
    end

    rows("UPDATE users SET status=0 WHERE id=$1", [c.actor.id])

    for {method, path} <- Enum.take(routes, 5) do
      assert_json(request(c.actor, method, path), 401, %{"error" => "User account is not active"})
    end

    id = area(c.actor)
    assert request(c.actor, :delete, "/api/v1/areas/#{id}").status == 200
    System.put_env("DAWARICH_RAILS", "on")

    server = Dawarich.Test.RawHTTP.listen()
    previous_upstream = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      :gen_tcp.close(server.listen)
      Application.put_env(:dawarich, :rails_upstream, previous_upstream)
    end)

    parent = self()
    start_supervised!({Task, fn -> upstream(server, parent) end})

    for {method, path} <- routes do
      conn = request(c.actor, method, path)
      assert conn.status == 218
      assert conn.resp_body == "Rails"
      assert_receive {:upstream, line, body}
      assert body == "{}"
      assert line == String.upcase(to_string(method)) <> " " <> path <> " HTTP/1.1"
    end
  end

  @tag :gap_render
  test "standalone API response failures roll back domain writes and after commit jobs", c do
    context = %{render_response: fn _ -> raise "synthetic render failure" end}
    marker(c.actor)
    assert request(c.actor, :delete, "/api/v1/demo_data", %{}, context: context).status == 500
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1", [c.actor.id]) == [[1]]
    rows("DELETE FROM imports WHERE user_id=$1", [c.actor.id])
    assert request(c.actor, :post, "/api/v1/demo_data", %{}, context: context).status == 500
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1", [c.actor.id]) == [[0]]
    stat(c.actor, 2024)

    assert request(c.actor, :post, "/api/v1/digests", %{"year" => 2024}, context: context).status ==
             500

    id = area(c.actor)
    visit(c.actor, id, place(c.actor))
    assert request(c.actor, :delete, "/api/v1/areas/#{id}", %{}, context: context).status == 500
    assert rows("SELECT id FROM areas WHERE id=$1", [id]) == [[id]]
    assert jobs(c.actor) == []
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  defp upstream(server, parent) do
    alias Dawarich.Test.RawHTTP
    socket = RawHTTP.accept(server)
    {head, rest} = RawHTTP.read_head(socket)
    size = RawHTTP.header(head, "content-length") |> List.first("0") |> String.to_integer()
    body = binary_part(RawHTTP.read_at_least(socket, rest, size), 0, size)
    send(parent, {:upstream, RawHTTP.request_line(head), body})
    RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
    :gen_tcp.close(socket)
    upstream(server, parent)
  end

  defp request(user, method, path, params \\ %{}, opts \\ []) do
    conn =
      Plug.Test.conn(method, path, Jason.encode!(params))
      |> put_req_header("content-length", to_string(byte_size(Jason.encode!(params))))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("accept-language", "de")
      |> assign(:api_context, opts[:context] || %{})

    conn =
      if Keyword.get(opts, :bearer, true),
        do: put_req_header(conn, "authorization", "Bearer " <> user.api_key),
        else: conn

    DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
  end

  defp assert_json(conn, status, body) do
    assert conn.status == status
    assert Jason.decode!(conn.resp_body) == body
    assert get_resp_header(conn, "location") == []
    conn
  end

  defp jobs(user),
    do:
      rows(
        "SELECT worker,args FROM oban.oban_jobs WHERE args->>'user_id'=$1 OR args->'payload'->>'user_id'=$1 ORDER BY id",
        [to_string(user.id)]
      )

  defp marker(user),
    do:
      rows(
        "INSERT INTO imports(user_id,name,source,status,demo,created_at,updated_at) VALUES($1,'Synthetic',6,2,true,now(),now())",
        [user.id]
      )

  defp stat(user, year),
    do:
      rows(
        "INSERT INTO stats(user_id,year,month,distance,created_at,updated_at) VALUES($1,$2,1,0,now(),now())",
        [user.id, year]
      )

  defp digest(user, year, period),
    do:
      rows(
        "INSERT INTO digests(user_id,year,month,period_type,created_at,updated_at) VALUES($1,$2,$3,$4,now(),now()) RETURNING id",
        [user.id, year, if(period == 0, do: 1), period]
      )
      |> hd()
      |> hd()

  defp area(user),
    do:
      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,100,now(),now()) RETURNING id",
        [user.id]
      )
      |> hd()
      |> hd()

  defp place(user),
    do:
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,source,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,1,now(),now()) RETURNING id",
        [user.id]
      )
      |> hd()
      |> hd()

  defp visit(user, area, place),
    do:
      rows(
        "INSERT INTO visits(user_id,area_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,$3,'Synthetic','2024-01-01','2024-01-01 01:00:00',3600,1,false,now(),now()) RETURNING id",
        [user.id, area, place]
      )
      |> hd()
      |> hd()

  defp fail_sql(table, event, actor, id) do
    rows(
      "CREATE FUNCTION public.api_gap_#{table}_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF #{actor}=#{id} THEN RAISE EXCEPTION 'synthetic SQL failure'; END IF; RETURN #{if(event == "DELETE", do: "OLD", else: "NEW")}; END $$"
    )

    rows(
      "CREATE TRIGGER api_gap_#{table}_failure BEFORE #{event} ON #{table} FOR EACH ROW EXECUTE FUNCTION public.api_gap_#{table}_failure()"
    )
  end
end
