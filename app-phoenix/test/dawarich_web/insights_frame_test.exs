defmodule DawarichWeb.InsightsFrameTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias DawarichWeb.{InsightsFrame, InsightsFrameLayout}

  test "actual Turbo Rails frame layout has only html/head/body and conditional Rails CSRF metas" do
    html =
      render_component(&InsightsFrameLayout.render/1, %{
        inner_content:
          Phoenix.HTML.raw("<turbo-frame id=\"insights_details\">synthetic</turbo-frame>"),
        rails_csrf_token: nil
      })

    assert html =~ "<html>"
    refute html =~ "<!DOCTYPE"
    refute html =~ "<title"
    refute html =~ "<nav"
    refute html =~ "<footer"
    refute html =~ "<script"
    refute html =~ "<meta"

    csrf =
      render_component(&InsightsFrameLayout.render/1, %{
        inner_content: "synthetic",
        rails_csrf_token: "synthetic-masked-token"
      })

    assert csrf =~ "csrf-param"
    assert csrf =~ "csrf-token"
    refute csrf =~ "phoenix-csrf-token"
  end

  test "actual lazy Turbo frame request retains its frame instead of forcing document reload" do
    conn =
      Plug.Test.conn(:get, "/insights/details?year=2024")
      |> put_req_header("turbo-frame", "insights_details")
      |> put_req_header("x-turbo-request-id", "synthetic-observed-turbo-request")
      |> DawarichWeb.InsightsVisit.call([])

    refute conn.halted

    for {method, path, frame} <- [
          {:get, "/", "insights_details"},
          {:post, "/insights/details", "insights_details"},
          {:get, "/insights/details", ""}
        ] do
      conn =
        Plug.Test.conn(method, path)
        |> put_req_header("turbo-frame", frame)
        |> put_req_header("x-turbo-request-id", "synthetic-observed-turbo-request")
        |> DawarichWeb.InsightsVisit.call([])

      assert conn.halted
      assert conn.resp_body =~ "turbo-visit-control"
    end
  end

  test "actual Rails details Vary follows present versus blank Accept" do
    for {accept, expected} <- [
          {nil, []},
          {"", []},
          {"text/html, application/xhtml+xml", ["Accept"]},
          {"*/*", ["Accept"]}
        ] do
      conn = Plug.Test.conn(:get, "/insights/details")
      conn = if accept, do: put_req_header(conn, "accept", accept), else: conn
      assert conn |> InsightsFrame.call([]) |> get_resp_header("vary") == expected
    end
  end

  test "frame request chooses minimal layout while direct/blank-header requests retain app root" do
    for {header, expected} <- [
          {nil, false},
          {"", false},
          {"  ", false},
          {"insights_details", true},
          {"other-frame", true}
        ] do
      conn = Plug.Test.conn(:get, "/insights/details")
      conn = if header, do: put_req_header(conn, "turbo-frame", header), else: conn
      conn = InsightsFrame.call(conn, [])
      assert conn.private.insights_frame == expected
      assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
      assert get_resp_header(conn, "x-dawarich-handler") == ["phoenix-insights"]
      assert InsightsFrame.live_session(conn)["insights_frame"] == expected
    end
  end
end
