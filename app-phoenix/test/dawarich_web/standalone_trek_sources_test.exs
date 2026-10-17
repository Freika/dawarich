defmodule DawarichWeb.StandaloneTrekSourcesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest, except: [post: 3]
  import Plug.Conn
  import Phoenix.LiveViewTest
  import Dawarich.Test.RawHTTP
  alias Dawarich.{ActiveRecordEncryption, Repo}
  alias Dawarich.Test.RailsUser
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
    {:ok, _view, html} = live(conn)
    doc = LazyHTML.from_document(html)

    assert LazyHTML.query(doc, "#trek-trips[phx-submit=import]") |> Enum.count() == 1

    assert LazyHTML.query(doc, "input[value=selected][checked]") |> Enum.count() == 1
    assert LazyHTML.query(doc, "input[disabled]") |> Enum.count() == 2
    assert html =~ "&lt;script&gt;"
    Task.await(task)
    task = provider(c, remote)
    localized = page(c, id, "?locale=de")
    assert localized.status == 200
    assert localized.resp_body =~ ~s(lang="de")
    {:ok, _view, _html} = live(localized)
    assert Dawarich.Accounts.settings(c.actor.id)["locale"] == "de"
    Task.await(task)
    rows("UPDATE users SET settings=$2 WHERE id=$1", [c.actor.id, c.actor.settings])
    task = provider(c, [], 401)
    assert {:error, {:redirect, %{to: to}}} = live(page(c, id))
    assert to == integrations()
    Task.await(task)

    assert rows("SELECT status,last_error FROM trip_sources WHERE id=$1", [id]) == [
             [1, "TREK request failed with HTTP 401"]
           ]

    assert get_resp_header(page(c, id), "location") == [integrations()]
  end

  defp page(c, id, suffix \\ ""),
    do:
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> RailsUser.connecting_as(c.actor.id)
      |> get("/settings/trek_sources/#{id}/select_trips" <> suffix)

  defp integrations, do: "/settings/integrations?service=trek"
  defp rows(sql, params), do: Repo.query!(sql, params, log: false).rows

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
end
