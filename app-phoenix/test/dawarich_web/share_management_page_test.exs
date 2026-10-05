defmodule DawarichWeb.ShareManagementPageTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Dawarich.Test.RawHTTP
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    actor = FrameSeeds.seed_management!("hub_active_shared_en")
    %{actor: actor}
  end

  defp element?(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.any?()

  test "full sharing pages boot their modal controllers without a LiveView mount", ctx do
    Repo.query!("DELETE FROM shared_links WHERE user_id = $1", [ctx.actor.id])

    for path <- ~w(/share_links/hub /share_links/live/new /trips/99101/share_link/new) do
      html = RailsUser.signed_in(ctx.actor.id) |> get(path) |> html_response(200)

      controller? =
        element?(html, "[phx-hook='RailsStimulus'] [data-controller='share-link-modal']")

      phrase? =
        element?(html, "[phx-hook='RailsStimulus'] input[name='shared_link[magic_phrase]']")

      assert controller?, path
      assert phrase?, path
    end
  end

  test "hub frame retains live timeline shared tab forms and indicators", ctx do
    html =
      RailsUser.signed_in(ctx.actor.id)
      |> get("/share_links/hub?tab=shared")
      |> html_response(200)

    assert element?(html, "turbo-frame#share-link-modal #share-hub-body")
    assert element?(html, "[data-controller='hub-tabs'][data-hub-tabs-active-value='shared']")

    for tab <- ~w(live timeline make shared),
        do: assert(element?(html, "[data-testid='hub-tab-#{tab}']"))

    assert element?(html, "form[action^='/share_links/live/regenerate']")
    assert element?(html, "form[action^='/share_links/timeline/regenerate']")

    assert element?(
             html,
             "form[action^='/share_links/shares/'] input[name='_method'][value='patch']"
           )

    assert element?(html, "[data-controller='clipboard']")
    assert element?(html, "[data-testid='hub-make-video']")
    assert element?(html, "[data-testid='hub-make-poster']")

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_document(html), "form[action^='/share_links/shares/']")
           ) == 5

    Repo.query!("DELETE FROM shared_links WHERE user_id = $1", [ctx.actor.id])

    empty =
      RailsUser.signed_in(ctx.actor.id)
      |> get("/share_links/hub?tab=shared")
      |> html_response(200)

    assert element?(empty, "[data-hub-tabs-active-value='live']")
    assert element?(empty, "form[action^='/share_links/live?']")
    assert element?(empty, "form[action^='/share_links/timeline?']")
    refute element?(empty, "[data-testid='hub-tab-shared']")
  end

  test "live and trip new support full document and exact frame header", ctx do
    for path <- ~w(/share_links/live/new /trips/99101/share_link/new) do
      conn = RailsUser.signed_in(ctx.actor.id) |> get(path)
      assert conn.status == 200
      assert element?(conn.resp_body, "html head meta[name='csrf-token']")
      assert element?(conn.resp_body, "turbo-frame#share-link-modal")
      assert element?(conn.resp_body, "form input[name='authenticity_token']")

      frame =
        RailsUser.signed_in(ctx.actor.id)
        |> Plug.Conn.put_req_header("turbo-frame", "share-link-modal")
        |> Plug.Conn.put_req_header("accept", "text/html")
        |> get(path)

      assert frame.status == 200
      refute frame.resp_body =~ "<!DOCTYPE html>"
      assert element?(frame.resp_body, "turbo-frame#share-link-modal")
      assert element?(frame.resp_body, "input[readonly]")
      assert Plug.Conn.get_resp_header(frame, "vary") == ["Accept"]
    end

    Repo.query!("DELETE FROM shared_links WHERE user_id = $1", [ctx.actor.id])

    trip =
      RailsUser.signed_in(ctx.actor.id)
      |> get("/trips/99101/share_link/new")
      |> html_response(200)

    assert element?(trip, "form[action='/trips/99101/share_link']")

    assert element?(
             trip,
             "input[name='shared_link[settings][show_stats]'][type='checkbox'][checked]"
           )

    live = RailsUser.signed_in(ctx.actor.id) |> get("/share_links/live/new") |> html_response(200)
    assert element?(live, "form[action='/share_links/live']")
    assert element?(live, "input[name='shared_link[magic_phrase]']")

    for path <- ~w(/trips/99102/share_link/new /trips/99999/share_link/new) do
      assert RailsUser.signed_in(ctx.actor.id) |> get(path) |> response(404) == "Not found"
    end

    assert build_conn() |> get("/share_links/live/new") |> redirected_to() ==
             "http://www.example.com/users/sign_in"

    upstream = upstream()

    task =
      Task.async(fn ->
        RailsUser.signed_in(ctx.actor.id)
        |> Plug.Conn.put_req_header("turbo-frame", "wrong-frame")
        |> get("/share_links/live/new")
      end)

    socket = accept(upstream)
    {head, _} = read_head(socket)
    assert header(head, "turbo-frame") == ["wrong-frame"]
    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    assert Task.await(task).resp_body == "rails"
    :gen_tcp.close(socket)

    Repo.query!(
      "INSERT INTO shared_links (id, user_id, resource_type, name, settings, created_at, updated_at) VALUES ('a9f10000-0000-4000-8000-000000000005', $1, 2, 'Fixture timeline', $2, now(), now())",
      [ctx.actor.id, %{"start_date" => "malformed", "end_date" => "2026-09-07"}]
    )

    task = Task.async(fn -> RailsUser.signed_in(ctx.actor.id) |> get("/share_links/hub") end)
    socket = accept(upstream)
    {head, _} = read_head(socket)
    assert request_line(head) == "GET /share_links/hub HTTP/1.1"
    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    assert Task.await(task).resp_body == "rails"
    :gen_tcp.close(socket)
  end

  test "trip shares key leaves trip page owned and hands back nested share route", ctx do
    upstream = upstream()
    rails_routes(["trip_shares"])
    Repo.query!("UPDATE trips SET visited_countries = $1 WHERE id = 99101", [["Germany"]])

    for path <- ~w(/trips /trips/99101) do
      conn =
        RailsUser.signed_in(ctx.actor.id)
        |> Map.merge(%{
          method: "GET",
          request_path: path,
          path_info: String.split(path, "/", trim: true),
          query_string: "",
          host: "www.example.com"
        })

      task = Task.async(fn -> DawarichWeb.Strangler.call(conn, []) end)
      assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 100)
      refute Task.await(task).halted
    end

    for key <- ~w(trip_shares trips) do
      Application.put_env(:dawarich, :rails_routes, [key])

      task =
        Task.async(fn ->
          RailsUser.signed_in(ctx.actor.id) |> get("/trips/99101/share_link/new")
        end)

      socket = accept(upstream)
      {head, _} = read_head(socket)
      assert request_line(head) == "GET /trips/99101/share_link/new HTTP/1.1"
      reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
      assert Task.await(task).resp_body == "rails"
      :gen_tcp.close(socket)
    end
  end

  test "share links key does not hand back public s", ctx do
    upstream = upstream()
    rails_routes(["share_links"])
    path = "/s/a9f10000-0000-4000-8000-000000000002"
    task = Task.async(fn -> Plug.Test.conn("GET", path) |> DawarichWeb.Strangler.call([]) end)
    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 100)
    refute Task.await(task).halted
    task = Task.async(fn -> RailsUser.signed_in(ctx.actor.id) |> get("/share_links/hub") end)
    socket = accept(upstream)
    {head, _} = read_head(socket)
    assert request_line(head) == "GET /share_links/hub HTTP/1.1"
    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    assert Task.await(task).resp_body == "rails"
    :gen_tcp.close(socket)
  end

  defp rails_routes(routes) do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, routes)
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)
  end

  defp upstream do
    saved = Application.get_env(:dawarich, :rails_upstream)
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, saved)
      :gen_tcp.close(upstream.listen)
    end)

    upstream
  end
end
