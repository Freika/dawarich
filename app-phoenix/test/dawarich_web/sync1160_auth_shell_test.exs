defmodule DawarichWeb.Sync1160AuthShellTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    Dawarich.State.put_registration_enabled(Repo, true)
    :ok
  end

  test "guest root redirects to sign-in carrying selected locale and unconsumed flash" do
    cookie =
      RailsUser.cookie(%{
        "flash" => %{"discard" => [], "flashes" => %{"notice" => "Synthetic root notice"}}
      })

    conn = build_conn() |> put_req_cookie("_dawarich_session", cookie) |> get("/?locale=de")
    assert conn.status == 302
    assert URI.parse(hd(get_resp_header(conn, "location"))).path == "/users/sign_in"
    next = conn |> recycle() |> get("/users/sign_in")
    assert next.status == 200
    assert next.resp_body =~ "Synthetic root notice"
    assert next.resp_body =~ "lang=\"de\""

    refute next |> recycle() |> get("/users/sign_in") |> Map.fetch!(:resp_body) =~
             "Synthetic root notice"
  end

  test "signed-in root redirects to preferred native map with locale and flash intact" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "root-#{id}@example.invalid"})
    conn = RailsUser.signed_in(id) |> get("/?locale=fr")
    assert conn.status == 302
    assert URI.parse(hd(get_resp_header(conn, "location"))).path == "/map/v2"
  end

  test "sign-in locale navigation renders every requested locale" do
    for locale <- ~w(en ca de es fr pl zh) do
      conn = get(build_conn(), "/users/sign_in?locale=" <> locale)
      assert conn.status == 200
      assert conn.resp_body =~ ~s(lang="#{locale}")
      refute conn.resp_body =~ "translation_missing"
    end
  end

  test "auth navigation omits self and irrelevant recovery links and all locales expose a password hint" do
    for locale <- ~w(en ca de es fr pl zh) do
      login =
        DawarichWeb.AuthForm.render("synthetic", "", locale: locale, registration_enabled: true)

      refute login =~ ~s(href="/users/sign_in")
      assert login =~ ~s(href="/users/unlock/new")
      assert login =~ ~s(href="/users/sign_up")
      refute login =~ "translation_missing"

      disabled =
        DawarichWeb.AuthForm.render("synthetic", "", locale: locale, registration_enabled: false)

      refute disabled =~ ~s(href="/users/sign_up")

      signup =
        DawarichWeb.AuthRegistration.Form.render("synthetic", "", [], nil, locale)
        |> IO.iodata_to_binary()

      refute signup =~ "translation_missing"
      assert signup =~ ~s(aria-describedby="password-hint")
      assert signup =~ "12"
      assert signup =~ ~s(href="/users/sign_in")
      refute signup =~ ~s(href="/users/sign_up")
      refute signup =~ ~s(href="/users/unlock/new")
    end
  end
end
