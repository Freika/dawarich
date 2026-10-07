defmodule DawarichWeb.StandaloneTrekSourcesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest, except: [post: 3]
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.{ActiveRecordEncryption, Repo}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "trek-owner@dawarich.test",
        settings: %{"locale" => "en", "timezone" => "UTC"}
      })

    other =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "trek-other@dawarich.test"
      })

    server = listen()

    on_exit(fn ->
      :gen_tcp.close(server.listen)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    %{
      actor: actor,
      other: other,
      server: server,
      url: "http://127.0.0.1:#{server.port}",
      session: RailsUser.session(actor.id)
    }
  end

  test "standalone TREK add verifies encrypts and reconnects without replacing an import claim",
       c do
    task = provider(c, [], 200, "replacement")
    conn = post(c, "", source_params(c, "replacement"))
    assert conn.status == 302

    [[id, url, encrypted]] =
      rows("SELECT id,base_url,api_key FROM trip_sources WHERE user_id=$1", [c.actor.id])

    assert url == c.url
    {:ok, key} = ActiveRecordEncryption.key()
    assert {:ok, "replacement"} = ActiveRecordEncryption.decrypt(encrypted, key)

    redirect(
      conn,
      "/settings/trek_sources/#{id}/select_trips",
      "notice",
      "TREK connected. Choose the trips you want Dawarich to manage."
    )

    Task.await(task)
    rows("UPDATE trip_sources SET status=1,last_error='expired' WHERE id=$1", [id])
    task = provider(c, [], 200, "renewed")

    redirect(
      post(c, "", source_params(c, "renewed")),
      "/settings/trek_sources/#{id}/select_trips",
      "notice",
      "TREK connected. Choose the trips you want Dawarich to manage."
    )

    Task.await(task)
    assert rows("SELECT status,last_error FROM trip_sources WHERE id=$1", [id]) == [[0, nil]]
    rows("UPDATE trip_sources SET importing=true WHERE id=$1", [id])
    blocked = post(c, "", source_params(c, "forbidden"))
    redirect(blocked, integrations(), "alert", "TREK is still importing your selected trips.")
    [[encrypted]] = rows("SELECT api_key FROM trip_sources WHERE id=$1", [id])
    assert {:ok, "renewed"} = ActiveRecordEncryption.decrypt(encrypted, key)
    rows("UPDATE trip_sources SET importing=false WHERE id=$1", [id])
    task = provider(c, [], 302)

    redirect(
      post(c, "", source_params(c, "synthetic-trek-key")),
      integrations(),
      "alert",
      "TREK request failed with HTTP 302"
    )

    Task.await(task)
    assert post(c, "", %{}).status == 400

    redirect(
      post(c, "", %{"trip_source" => %{"base_url" => "", "api_key" => ""}}),
      integrations(),
      "alert",
      "Base url can't be blank and Api key can't be blank"
    )
  end

  test "standalone TREK selection renders dated active choices and records provider failures",
       c do
    id = source(c)
    trip(c, id, "selected")

    remote = [
      remote("selected"),
      Map.put(remote("archived"), "archived", true),
      %{"id" => "undated", "title" => "<script>"}
    ]

    task = provider(c, remote)
    conn = page(c, id)
    assert conn.status == 200
    doc = LazyHTML.from_document(conn.resp_body)

    assert LazyHTML.query(
             doc,
             "form[action='/settings/trek_sources/#{id}/import_trips'] input[name=authenticity_token]"
           )
           |> LazyHTML.attribute("value") != []

    assert LazyHTML.query(doc, "input[value=selected][checked]") |> Enum.count() == 1
    assert LazyHTML.query(doc, "input[disabled]") |> Enum.count() == 2
    assert conn.resp_body =~ "&lt;script&gt;"
    Task.await(task)
    task = provider(c, remote)
    localized = page(c, id, ".html?locale=de&format=html")
    assert localized.status == 200
    assert localized.resp_body =~ ~s(lang="de")
    assert Dawarich.Accounts.settings(c.actor.id)["locale"] == "de"
    Task.await(task)
    rows("UPDATE users SET settings=$2 WHERE id=$1", [c.actor.id, c.actor.settings])
    task = provider(c, [], 401)
    redirect(page(c, id), integrations(), "alert", "TREK request failed with HTTP 401")
    Task.await(task)

    assert rows("SELECT status,last_error FROM trip_sources WHERE id=$1", [id]) == [
             [1, "TREK request failed with HTTP 401"]
           ]

    redirect(
      page(c, id),
      integrations(),
      "alert",
      "TREK is disabled. Reconnect it with a new API key before syncing."
    )
  end

  test "standalone TREK import filters all identifiers claims once and atomically publishes the native job",
       c do
    id = source(c)
    own("imports.trek_import")
    ids = Enum.map(1..101, &to_string/1)

    rows(
      "ALTER TABLE job_outbox ADD CONSTRAINT trek_publish_probe CHECK(aggregate_id <> #{id}) NOT VALID"
    )

    try do
      task = provider(c, [remote("1")])
      assert post(c, "/#{id}/import_trips", %{"trip_ids" => ["1"]}).status == 500
      Task.await(task)

      assert rows("SELECT importing,selection_token FROM trip_sources WHERE id=$1", [id]) == [
               [false, "original"]
             ]

      assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    after
      rows("ALTER TABLE job_outbox DROP CONSTRAINT trek_publish_probe")
    end

    task =
      provider(
        c,
        Enum.map(ids, &remote/1) ++
          [Map.put(remote("archived"), "archived", true), %{"id" => "undated"}]
      )

    submitted = ids ++ ["1", "", "archived", "undated", "unknown"]
    conn = post(c, "/#{id}/import_trips", %{"trip_ids" => submitted})
    redirect(conn, integrations(), "notice", "Selected TREK trips are being synchronized.")
    Task.await(task)
    [[true, token]] = rows("SELECT importing,selection_token FROM trip_sources WHERE id=$1", [id])
    assert is_binary(token) and byte_size(token) > 0

    assert rows("SELECT command_type,payload,aggregate_id FROM job_outbox") == [
             [
               "imports.trek_import",
               %{
                 "source_id" => id,
                 "identifiers" => ids,
                 "selection_token" => token,
                 "offset" => 0
               },
               id
             ]
           ]

    redirect(
      post(c, "/#{id}/import_trips", %{"trip_ids" => ["2"]}),
      integrations(),
      "alert",
      "TREK is still importing your selected trips."
    )

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    rows("UPDATE trip_sources SET importing=false WHERE id=$1", [id])
    task = provider(c, [%{"id" => "undated"}])

    redirect(
      post(c, "/#{id}/import_trips", %{"trip_ids" => ["undated"]}),
      "/settings/trek_sources/#{id}/select_trips",
      "alert",
      "Select at least one active TREK trip with start and end dates."
    )

    Task.await(task)
  end

  test "standalone TREK empty selection rotates its token and stops trips without deleting itineraries",
       c do
    id = source(c)
    tid = trip(c, id, "selected")

    redirect(
      post(c, "/#{id}/import_trips", %{}),
      integrations(),
      "notice",
      "No TREK trips selected. Existing itineraries were kept and stopped syncing."
    )

    assert rows(
             "SELECT source_status,trip_source_id,source_synced_at IS NOT NULL FROM trips WHERE id=$1",
             [tid]
           ) == [[1, id, true]]

    assert rows("SELECT importing,selection_token <> 'original' FROM trip_sources WHERE id=$1", [
             id
           ]) == [[false, true]]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  test "standalone TREK manual sync queues the source and refuses disabled or importing sources",
       c do
    id = source(c)
    own("imports.trek_sync")

    redirect(
      post(c, "/#{id}/sync", %{}),
      integrations(),
      "notice",
      "TREK synchronization was queued."
    )

    assert rows("SELECT command_type,payload,aggregate_id FROM job_outbox") == [
             ["imports.trek_sync", %{"source_id" => id, "after_id" => nil}, id]
           ]

    rows("UPDATE trip_sources SET importing=true WHERE id=$1", [id])

    redirect(
      post(c, "/#{id}/sync", %{}),
      integrations(),
      "alert",
      "TREK is still importing your selected trips."
    )

    rows("UPDATE trip_sources SET status=1 WHERE id=$1", [id])

    redirect(
      post(c, "/#{id}/sync", %{}),
      integrations(),
      "alert",
      "TREK is disabled. Reconnect it with a new API key before syncing."
    )

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end

  test "standalone TREK disconnect removes even importing sources and retains managed trip data",
       c do
    id = source(c)
    tid = trip(c, id, "selected")
    rows("UPDATE trip_sources SET importing=true WHERE id=$1", [id])

    redirect(
      post(c, "/#{id}", %{"_method" => "delete"}),
      integrations(),
      "notice",
      "TREK was disconnected. Your managed trips were kept and will no longer sync."
    )

    assert rows("SELECT id FROM trip_sources WHERE id=$1", [id]) == []

    assert rows(
             "SELECT trip_source_id,source_status,name,source_identifier FROM trips WHERE id=$1",
             [tid]
           ) == [[nil, 1, "Kept itinerary", "selected"]]
  end

  test "standalone TREK routes require the owner active access and CSRF while coexistence still forwards",
       c do
    id = source(%{c | actor: c.other})

    for suffix <- ["/#{id}/sync", "/#{id}/import_trips", "/#{id}"] do
      params = if suffix == "/#{id}", do: %{"_method" => "delete"}, else: %{}
      assert post(c, suffix, params).status == 404
    end

    assert page(c, id).status == 404
    anonymous = post(%{c | session: %{}}, "/#{id}/sync", %{})

    redirect(
      anonymous,
      "/users/sign_in",
      "alert",
      "You need to sign in or sign up before continuing."
    )

    own_id = source(c)
    assert post(c, "/#{own_id}/sync", %{"authenticity_token" => "bad"}).status == 422
    rows("UPDATE users SET active_until=now()-interval '1 day' WHERE id=$1", [c.actor.id])
    assert post(c, "/#{own_id}/sync", %{}).status == 303
    rows("UPDATE users SET active_until='3026-01-01',plan=0 WHERE id=$1", [c.actor.id])
    System.put_env("SELF_HOSTED", "false")
    assert post(c, "/#{own_id}/sync", %{}).status == 303
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "on")
    upstream = RailsFormRequests.upstream!()

    {{line, _}, conn} =
      RailsFormRequests.forwarded(upstream, fn -> post(c, "/#{own_id}/sync", %{}) end)

    assert line == "POST /settings/trek_sources/#{own_id}/sync HTTP/1.1"
    assert conn.status == 204
  end

  defp post(c, suffix, params) do
    params = Map.merge(%{"authenticity_token" => RailsCsrf.masked_token(c.session)}, params)

    body =
      Enum.flat_map(params, fn
        {"trip_ids", ids} -> Enum.map(ids, &{"trip_ids[]", &1})
        {"trip_source", attrs} -> Enum.map(attrs, fn {k, v} -> {"trip_source[#{k}]", v} end)
        pair -> [pair]
      end)
      |> URI.encode_query()

    RailsFormRequests.post_form(
      c.session,
      body,
      [{"accept", "text/html"}],
      "/settings/trek_sources" <> suffix
    )
  end

  defp page(c, id, suffix \\ ""),
    do:
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> get("/settings/trek_sources/#{id}/select_trips" <> suffix)

  defp source_params(c, key),
    do: %{"trip_source" => %{"base_url" => "  " <> c.url <> "/  ", "api_key" => key}}

  defp integrations, do: "/settings/integrations?service=trek"
  defp rows(sql, params \\ []), do: Repo.query!(sql, params, log: false).rows
  defp own(kind), do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)

  defp source(c) do
    {:ok, key} = ActiveRecordEncryption.key()

    [[id]] =
      rows(
        "INSERT INTO trip_sources(user_id,provider,base_url,api_key,selection_token,created_at,updated_at) VALUES($1,'trek',$2,$3,'original',now(),now()) RETURNING id",
        [c.actor.id, c.url, ActiveRecordEncryption.encrypt("synthetic-trek-key", key)]
      )

    id
  end

  defp trip(c, id, identifier) do
    [[tid]] =
      rows(
        "INSERT INTO trips(user_id,name,started_at,ended_at,trip_source_id,source_identifier,source_status,created_at,updated_at) VALUES($1,'Kept itinerary','2030-01-01','2030-01-02',$2,$3,0,now(),now()) RETURNING id",
        [c.actor.id, id, identifier]
      )

    tid
  end

  defp remote(id),
    do: %{
      "id" => id,
      "title" => "Trip #{id}",
      "archived" => false,
      "start_date" => "2030-01-01",
      "end_date" => "2030-01-02"
    }

  defp provider(c, trips, status \\ 200, key \\ "synthetic-trek-key") do
    Task.async(fn ->
      socket = accept(c.server)
      {head, _} = read_head(socket)
      assert request_line(head) == "GET /api/v1/trips HTTP/1.1"
      assert header(head, "authorization") == ["Bearer " <> key]
      body = Jason.encode!(%{"trips" => trips})

      reply(
        socket,
        "HTTP/1.1 #{status} OK\r\nLocation: http://other.example.test/trips\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
          body
      )

      :gen_tcp.close(socket)
    end)
  end

  defp redirect(conn, path, type, message) do
    assert conn.status == 302
    assert conn.resp_body == ""
    assert get_resp_header(conn, "location") == ["http://www.example.com" <> path]
    assert RailsFormRequests.rails_session(conn)["flash"]["flashes"][type] == message
  end
end
