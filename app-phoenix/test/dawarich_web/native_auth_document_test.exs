defmodule DawarichWeb.NativeAuthDocumentTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias DawarichWeb.{LayoutAssigns, Locale}

  defp admitted do
    Phoenix.ConnTest.build_conn(:get, "/users/sign_in")
    |> assign(:current_user, nil)
    |> assign(:rails_session, %{"flash" => %{"flashes" => %{"alert" => "Inherited alert"}}})
    |> fetch_query_params()
    |> Locale.call([])
    |> LayoutAssigns.call([])
    |> put_resp_cookie("_dawarich_session", "synthetic-signed-cookie",
      http_only: true,
      same_site: "Lax"
    )
    |> put_resp_header("x-dawarich-auth-owner", "native-credentials")
    |> put_resp_header("cache-control", "no-store")
  end

  defp authenticated do
    conn = admitted()
    version = Dawarich.Navbar.load(nil, now: conn.assigns.now, self_hosted: true).version

    user = %Dawarich.Accounts.User{
      id: 123,
      api_key: "synthetic-chrome-key",
      admin: true,
      status: 0,
      theme: "dark",
      plan: 0
    }

    navbar = %{
      version: version,
      subscription: nil,
      unread: %{count: 0, items: []},
      family: %{available: true, member: false, sharing: false},
      onboarding: false,
      supporter: false,
      imports: %{count: 0, demo: false}
    }

    conn |> assign(:current_user, user) |> assign(:navbar, navbar)
  end

  defp document(conn) do
    apply(DawarichWeb.AuthPageController, :document, [
      conn,
      Phoenix.HTML.raw("<main>Safe content</main>"),
      422,
      [
        chrome: if(conn.assigns.current_user, do: :authenticated, else: :anonymous),
        csrf_token: "synthetic-csrf",
        title: nil
      ]
    ])
  end

  test "HTTP auth document preserves response status headers cookie and one-request flash" do
    for conn <- [admitted(), authenticated()] do
      rendered = document(conn)
      assert rendered.status == 422 and rendered.halted
      assert get_resp_header(rendered, "cache-control") == ["no-store"]
      assert get_resp_header(rendered, "x-dawarich-auth-owner") == ["native-credentials"]
      assert rendered.resp_cookies == conn.resp_cookies
      assert rendered.assigns == conn.assigns

      assert Enum.count(
               LazyHTML.query(LazyHTML.from_document(rendered.resp_body), "[role=alert]")
             ) == 1

      assert rendered.resp_body =~ "Inherited alert"
      refute Map.has_key?(rendered.assigns.rails_session, "flash")
    end
  end

  test "HTTP auth document has no LiveView root or legacy runtime" do
    for conn <- [admitted(), authenticated()] do
      rendered = document(conn)
      html = rendered.resp_body
      assert html =~ ~s(src="/native/auth_http.js")

      for marker <-
            ~w(importmap data-phx-main data-phx-session /native/app.js /phoenix/live data-controller data-turbo),
          do: refute(html =~ marker, marker)

      assert html =~ ~s(name="csrf-param" content="authenticity_token")
      assert html =~ "Safe content"
    end
  end
end
