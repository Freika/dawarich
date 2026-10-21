defmodule DawarichWeb.PublicHomeTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.Auth.RegistrationSetting
  alias Dawarich.Test.RailsUser
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
    previous_jobs_repo = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
    Dawarich.Repo.query!("DELETE FROM phoenix.app_version", [], log: false)

    on_exit(fn ->
      case previous_jobs_repo do
        {:ok, repo} -> Application.put_env(:dawarich, :jobs_repo, repo)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    Dawarich.State.put_registration_enabled(Dawarich.Repo, true)
    RailsUser.insert!(%{id: 15701, email: "a10b-home@example.invalid"})
    {:ok, before} = Dawarich.Redis.cache_command(["GET", "dawarich/registration_enabled"])

    on_exit(fn ->
      if before,
        do: Dawarich.Redis.cache_command(["SET", "dawarich/registration_enabled", before]),
        else: Dawarich.Redis.cache_command(["DEL", "dawarich/registration_enabled"])
    end)

    :ok
  end

  @tag :a12f4_gate_home
  test "credentials and public home obey copied false while Cloud home keeps signup" do
    assert Dawarich.Jobs.repo() == Dawarich.Repo
    assert Code.ensure_loaded?(PublicHomeLive), "public home LiveView must exist"

    previous = System.get_env("SELF_HOSTED")
    flows = Application.get_env(:dawarich, :phoenix_auth)
    System.put_env("SELF_HOSTED", "true")
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")

      if flows,
        do: Application.put_env(:dawarich, :phoenix_auth, flows),
        else: Application.delete_env(:dawarich, :phoenix_auth)
    end)

    bytes = Dawarich.RailsCache.Wire.encode_boolean(true, expires_at: nil)
    {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", "dawarich/registration_enabled", bytes])
    :ok = RegistrationSetting.put(false)
    conn = DawarichWeb.AuthGate.call(Plug.Test.conn(:get, "/users/sign_in"), [])
    assert conn.status == 200
    refute conn.resp_body =~ ~s(href="/users/sign_up")

    for locale <- ~w(en de es fr pl ca zh) do
      conn = get(build_conn(), "/?locale=" <> locale)
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
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

    Dawarich.Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
    assert HomeGate.owned?(Plug.Test.conn(:get, "/"), %{})
  end

  test "registration-disabled Rails notice survives the guest transport join and is consumed once" do
    native_auth()
    :ok = RegistrationSetting.put(false)
    notice = "Registration is not available. Please contact your administrator for access."

    conn =
      build_conn()
      |> put_req_cookie(
        "_dawarich_session",
        RailsUser.cookie(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
      )
      |> get("/")

    assert_guest_notice(conn, notice)
  end

  test "native logout notice survives the guest transport join and is consumed once" do
    native_auth()
    session = RailsUser.session(15701)

    body =
      URI.encode_query(%{
        "_method" => "delete",
        "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)
      })

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> post("/users/sign_out", body)

    assert conn.status == 303
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-credentials"]
    assert get_resp_header(conn, "location") == ["http://www.example.com/"]
    assert_guest_notice(conn |> recycle() |> get("/"), "Signed out successfully.")
  end

  defp native_auth do
    previous = System.get_env("SELF_HOSTED")
    flows = Application.get_env(:dawarich, :phoenix_auth)
    System.put_env("SELF_HOSTED", "true")
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")

      if flows,
        do: Application.put_env(:dawarich, :phoenix_auth, flows),
        else: Application.delete_env(:dawarich, :phoenix_auth)
    end)
  end

  defp assert_guest_notice(conn, notice) do
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
    next = conn |> browser_recycle() |> get("/users/sign_in")
    assert next.status == 200
    assert next.resp_body =~ notice
    refute next |> browser_recycle() |> get("/users/sign_in") |> Map.fetch!(:resp_body) =~ notice
  end

  defp browser_recycle(conn) do
    conn = recycle(conn)
    cookie = conn |> get_req_header("cookie") |> Enum.join("; ")
    conn |> delete_req_header("cookie") |> put_req_header("cookie", cookie)
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
