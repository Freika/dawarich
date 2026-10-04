defmodule DawarichWeb.PublicHomeTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.Auth.RegistrationSetting
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.{HomeDispatch, HomeGate, PublicHomeLive}
  @endpoint DawarichWeb.Endpoint

  setup_all do
    if is_nil(Process.whereis(Dawarich.Redis.Cache)),
      do:
        start_supervised!(
          {Redix,
           {System.fetch_env!("PHOENIX_TEST_REDIS_URL"),
            [name: Dawarich.Redis.Cache, database: 0]}}
        )

    :ok
  end

  setup do
    level = Logger.level()
    Logger.configure(level: :critical)
    on_exit(fn -> Logger.configure(level: level) end)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    RailsUser.insert!(%{id: 15701, email: "a10b-home@example.invalid"})
    {:ok, before} = Dawarich.Redis.cache_command(["GET", "dawarich/registration_enabled"])

    on_exit(fn ->
      if before,
        do: Dawarich.Redis.cache_command(["SET", "dawarich/registration_enabled", before]),
        else: Dawarich.Redis.cache_command(["DEL", "dawarich/registration_enabled"])
    end)

    :ok
  end

  test "anonymous home matches Rails en de markup and registration links" do
    assert Code.ensure_loaded?(PublicHomeLive), "public home LiveView must exist"

    for locale <- ~w(en de), mode <- [:enabled, :disabled, :cloud] do
      :ok = RegistrationSetting.put(mode == :enabled)

      {:ok, view, html} =
        live_isolated(RailsUser.connecting_as(build_conn(), nil), PublicHomeLive,
          session: session(locale, mode != :cloud)
        )

      expected = File.read!("test/fixtures/welcome_home/home_#{locale}_#{mode}.html")
      assert ParityHTML.fragment(html, ".w-full.mx-auto.my-5") == ParityHTML.normalize(expected)
      meta = Jason.decode!(File.read!("test/fixtures/welcome_home/home_#{locale}_#{mode}.json"))
      assert ParityHTML.fragment(html, "div.navbar") == ParityHTML.normalize(meta["navbar"])
      assert ParityHTML.fragment(html, "footer") == ParityHTML.normalize(meta["footer"])
      assert has_element?(view, "a[href='/users/sign_in']")
      assert has_element?(view, "a[href='/users/sign_up']") == (mode != :disabled)
    end
  end

  test "signed in root retains InsightsHome response and connected login leaves public page" do
    assert Code.ensure_loaded?(HomeDispatch), "home dispatch must exist"
    conn = RailsUser.signed_in(15701) |> HomeDispatch.call([])
    assert conn.status == 302 and conn.resp_body == ""
    assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
    :ok = RegistrationSetting.put(true)
    conn = build_conn() |> RailsUser.connecting_as(15701)

    assert {:error, {:redirect, %{to: "/"}}} =
             live_isolated(conn, PublicHomeLive, session: session("en", true))

    assert HomeGate.owned?(Plug.Test.conn(:get, "/"), %{})

    for query <- ~w(client=mobile referral=x invitation_token=x pending_import_ticket=x) do
      refute HomeGate.owned?(Plug.Test.conn(:get, "/?" <> query), %{})
    end

    Dawarich.Redis.cache_command(["SET", "dawarich/registration_enabled", "invalid"])
    refute HomeGate.owned?(Plug.Test.conn(:get, "/"), %{})
  end

  test "anonymous connected event keeps the guest page usable" do
    assert Code.ensure_loaded?(PublicHomeLive), "public home LiveView must exist"
    :ok = RegistrationSetting.put(true)
    conn = build_conn() |> RailsUser.connecting_as(nil)
    {:ok, view, _html} = live_isolated(conn, PublicHomeLive, session: session("en", true))
    html = render_hook(view, "changelog_consent", %{"decision" => "granted"})
    assert html =~ "The only location history tracker"
    assert has_element?(view, "a[href='/users/sign_in']")
    assert render_hook(view, "lv:clear-flash", %{"key" => "notice"}) =~ "Location history"
  end

  defp session(locale, self_hosted) do
    %{
      "rails_user_id" => nil,
      "locale" => locale,
      "suggested_locale" => nil,
      "self_hosted" => self_hosted,
      "request_path" => "/",
      "query_params" => %{},
      "base_url" => "http://www.example.com",
      "rails_csrf_token" => "synthetic",
      "flash_messages" => [{"notice", "Synthetic guest flash"}]
    }
  end
end
