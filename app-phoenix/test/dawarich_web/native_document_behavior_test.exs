defmodule DawarichWeb.NativeDocumentBehaviorTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    context = NativeAdminUI.setup!()
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    context
  end

  test "HTML document aliases preserve filters privacy and admission", %{actor: actor} do
    for path <- ["/places.html?search=native&page=2", "/places?format=html&search=native&page=2"] do
      conn = NativeAdminUI.conn(actor) |> get(path)
      assert conn.status == 200
      assert conn.query_params["search"] == "native"
      assert conn.query_params["page"] == "2"
      refute String.contains?(conn.resp_body, actor.api_key)
      assert String.contains?(conn.resp_body, "<html")
      guest = build_conn() |> get(path)
      assert guest.status == 302
      assert URI.parse(hd(get_resp_header(guest, "location"))).path == "/users/sign_in"

      {:ok, stored} =
        Dawarich.RailsCookies.decrypt(
          guest.resp_cookies["_dawarich_session"].value,
          "_dawarich_session",
          Dawarich.RailsSecret.fetch(),
          DateTime.utc_now()
        )

      assert stored["user_return_to"] == path
    end
  end

  test "native documents render full accessible pages without frame envelopes", %{actor: actor} do
    for path <- ~w(/tags /settings/general /imports /exports /share_links/hub) do
      conn =
        NativeAdminUI.conn(actor)
        |> put_req_header("turbo-frame", "old-frame")
        |> put_req_header("x-turbo-request-id", "old-visit")
        |> get(path)

      assert conn.status == 200
      assert String.contains?(conn.resp_body, "/native/app")
      refute String.contains?(conn.resp_body, "<turbo-frame")
      refute String.contains?(conn.resp_body, "turbo-visit-control")
    end
  end

  test "unsupported legacy frame formats fail locally without mutations", %{actor: actor} do
    for path <-
          ~w(/tags.turbo_stream /tags?format=turbo_stream /share_links/hub?format=turbo_stream) do
      {conn, queries} = NativeAdminUI.queries(fn -> NativeAdminUI.conn(actor) |> get(path) end)
      assert conn.status in [406, 422]
      assert get_resp_header(conn, "location") == []
      refute Enum.any?(queries, &String.match?(&1, ~r/\A\s*(INSERT|UPDATE|DELETE)\b/i))
    end

    conn =
      NativeAdminUI.conn(actor) |> put_req_header("accept", "text/javascript") |> get("/tags")

    assert conn.status in [406, 422]
  end

  test "native refusal redirects once to its authorized destination" do
    guest =
      build_conn() |> put_req_header("x-requested-with", "XMLHttpRequest") |> get("/tags.html")

    assert guest.status == 302
    path = URI.parse(hd(get_resp_header(guest, "location"))).path
    assert path == "/users/sign_in"
    destination = build_conn() |> get(path)
    assert destination.status == 200
    assert get_resp_header(destination, "location") == []
  end

  test "removing route gates does not repeat native page queries", %{actor: actor} do
    {conn, queries} =
      NativeAdminUI.queries(fn ->
        NativeAdminUI.conn(actor) |> get("/settings/background_jobs")
      end)

    assert conn.status == 200
    users = Enum.count(queries, &String.match?(&1, ~r/FROM "?users"?/i))
    IO.puts("native background admission user reads=#{users} total=#{length(queries)}")
    assert users > 0
    assert length(queries) <= 16
  end
end
