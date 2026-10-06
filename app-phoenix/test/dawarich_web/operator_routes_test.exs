defmodule DawarichWeb.OperatorRoutesTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Dawarich.{Accounts, RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AdminGate, AdminLiveAuth, Endpoint}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    saved =
      Map.new(
        ~w(SELF_HOSTED SIDEKIQ_USERNAME SIDEKIQ_PASSWORD JWT_SECRET_KEY),
        &{&1, System.get_env(&1)}
      )

    upstream = Application.get_env(:dawarich, :rails_upstream)
    System.put_env("SELF_HOSTED", "true")
    System.put_env("JWT_SECRET_KEY", "synthetic-operator-jwt")
    System.delete_env("SIDEKIQ_USERNAME")
    System.delete_env("SIDEKIQ_PASSWORD")
    Application.put_env(:dawarich, :rails_upstream, nil)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Dawarich.State.put_registration_enabled(Repo, false)

    on_exit(fn ->
      Enum.each(saved, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      Application.put_env(:dawarich, :rails_upstream, upstream)
    end)

    for {id, admin} <- [{10001, true}, {10002, false}] do
      RailsUser.insert!(%{
        id: id,
        email: "operator-#{id}@example.invalid",
        admin: admin,
        settings: %{"timezone" => "Europe/Berlin"}
      })
    end

    :ok
  end

  test "authorized legacy Sidekiq URL redirects temporarily to native job health" do
    for method <- [:get, :head], query <- ["", "?return_to=https://example.invalid", "?flag"] do
      response = request(method, "/sidekiq" <> query, 10001)
      assert response.status == 302
      assert get_resp_header(response, "location") == ["/settings/background_jobs"]
      assert get_resp_header(response, "www-authenticate") == []
      if method == :head, do: assert(response.resp_body == "")
    end

    page = request(:get, "/settings/background_jobs", 10001)
    assert page.status == 200
    assert page.resp_body =~ ~s(data-testid="instance-settings-phoenix-jobs")

    assert Phoenix.Router.route_info(DawarichWeb.Router, "POST", "/sidekiq", "localhost") ==
             :error

    assert Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/sidekiq/queues", "localhost") ==
             :error
  end

  test "legacy operator URLs preserve guest nonadmin and Cloud authorization" do
    for id <- [nil, 10002] do
      response = request(:get, "/sidekiq", id)
      assert response.status == 302
      assert get_resp_header(response, "location") == ["/"]

      assert {:ok, session} =
               RailsCookies.decrypt(
                 response.resp_cookies["_dawarich_session"].value,
                 "_dawarich_session",
                 RailsSecret.fetch(),
                 DateTime.utc_now()
               )

      assert session["flash"]["flashes"]["error"] ==
               "You are not authorized to perform this action."
    end

    assert AdminGate.background?(signed(:get, "/settings/background_jobs", 10002), %{})
    System.put_env("SELF_HOSTED", "false")
    assert get_resp_header(request(:get, "/sidekiq", 10001), "location") == ["/"]

    System.put_env("SIDEKIQ_USERNAME", "synthetic-operator")
    System.put_env("SIDEKIQ_PASSWORD", "synthetic-password")

    for credentials <- [nil, "synthetic-operator:wrong", "wrong:synthetic-password"] do
      response = request(:get, "/sidekiq", 10001, credentials)
      assert response.status == 401
      assert get_resp_header(response, "www-authenticate") == [~s(Basic realm="Restricted Area")]
    end

    for id <- [nil, 10002] do
      response = request(:get, "/sidekiq", id, "synthetic-operator:synthetic-password")
      assert get_resp_header(response, "location") == ["/"]
    end

    response = request(:head, "/sidekiq", 10001, "synthetic-operator:synthetic-password")
    assert response.status == 302
    assert get_resp_header(response, "location") == ["/settings/background_jobs"]
  end

  test "Cloud job health requires Basic authorization on HTTP and connected mounts" do
    cloud!()

    for method <- [:get, :head],
        credentials <- [nil, "synthetic-operator:wrong", "wrong:synthetic-password"] do
      response = request(method, "/settings/background_jobs", 10001, credentials)
      assert response.status == 401
      assert get_resp_header(response, "www-authenticate") == [~s(Basic realm="Restricted Area")]
      refute response.resp_body =~ ~s(data-testid="instance-settings-phoenix-jobs")
    end

    refute AdminGate.background?(signed(:get, "/settings/background_jobs", 10001), %{})
    refute AdminGate.background?(signed(:get, "/settings/background_jobs", 10002), %{})
    conn = basic(signed(:get, "/settings/background_jobs", 10001))
    assert AdminGate.background?(conn, %{})

    page = request(:get, "/settings/background_jobs", 10001, credentials())
    assert page.status == 200
    assert page.resp_body =~ ~s(data-testid="instance-settings-phoenix-jobs")
    assert request(:head, "/settings/background_jobs", 10001, credentials()).resp_body == ""

    for authorization <- [nil, "invalid"] do
      session = Map.put(session(), "operator_authorization", authorization)
      assert {:halt, rejected} = AdminLiveAuth.on_mount(:background, %{}, session, socket())
      assert rejected.redirected == {:redirect, %{to: "/settings/background_jobs", status: 302}}
    end

    session = DawarichWeb.OperatorRedirect.live_session(conn) |> Map.merge(session())
    assert {:cont, mounted} = AdminLiveAuth.on_mount(:background, %{}, session, socket())
    assert mounted.redirected == nil
    System.put_env("SIDEKIQ_PASSWORD", "synthetic-rotated")
    assert {:halt, revoked} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, mounted)
    assert revoked.redirected == {:redirect, %{to: "/settings/background_jobs", status: 302}}
  end

  test "self hosted demotion clears cached job health while retaining background settings" do
    assert {:cont, mounted} = AdminLiveAuth.on_mount(:background, %{}, session(), socket())
    assert {:ok, mounted} = DawarichWeb.SettingsLive.BackgroundJobs.mount(%{}, session(), mounted)
    assert mounted.assigns.health
    assert render_health(mounted) =~ ~s(data-testid="instance-settings-phoenix-jobs")

    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)
    assert {:halt, demoted} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, mounted)
    assert demoted.redirected == nil
    refute demoted.assigns.current_user.admin
    assert demoted.assigns.health == nil
    refute render_health(demoted) =~ ~s(data-testid="instance-settings-phoenix-jobs")

    stale = Phoenix.Component.assign(demoted, :health, mounted.assigns.health)
    refute render_health(stale) =~ ~s(data-testid="instance-settings-phoenix-jobs")
    assert AdminGate.background?(signed(:get, "/settings/background_jobs", 10001), %{})
  end

  test "Cloud job health role refresh redirects demoted operators and retains authorized operators" do
    cloud!()
    conn = basic(signed(:get, "/settings/background_jobs", 10001))
    session = DawarichWeb.OperatorRedirect.live_session(conn) |> Map.merge(session())
    assert {:cont, mounted} = AdminLiveAuth.on_mount(:background, %{}, session, socket())
    assert {:halt, authorized} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, mounted)
    assert authorized.redirected == nil
    assert authorized.assigns.current_user.admin

    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)
    assert {:halt, demoted} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, authorized)
    assert demoted.redirected == {:redirect, %{to: "/settings/background_jobs", status: 302}}
  end

  test "Flipper root and nested URLs are retired native 404s with no Rails fallback" do
    previous = Application.get_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, ["admin"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, previous) end)

    for hosted <- ["true", "false"],
        id <- [nil, 10001, 10002],
        method <- [:get, :head, :post, :patch, :delete],
        path <- [
          "/admin/flipper",
          "/admin/flipper/features",
          "/admin/flipper/features/example?format=json"
        ] do
      System.put_env("SELF_HOSTED", hosted)
      response = request(method, path, id)
      assert {response.status, response.resp_body} == {404, ""}
      assert get_resp_header(response, "location") == []
    end

    refute Enum.any?(DawarichWeb.RateLimit.Rules.throttles(), &(elem(&1, 0) == "admin/flipper"))
  end

  defp cloud! do
    System.put_env("SELF_HOSTED", "false")
    System.put_env("SIDEKIQ_USERNAME", "synthetic-operator")
    System.put_env("SIDEKIQ_PASSWORD", "synthetic-password")
  end

  defp credentials, do: "synthetic-operator:synthetic-password"

  defp basic(conn),
    do: put_req_header(conn, "authorization", "Basic " <> Base.encode64(credentials()))

  defp session do
    %{
      "rails_user_id" => 10001,
      "locale" => "en",
      "self_hosted" => DawarichWeb.LayoutAssigns.self_hosted?(),
      "request_path" => "/settings/background_jobs",
      "query_params" => %{},
      "rails_csrf_token" => "CSRF",
      "base_url" => "http://localhost"
    }
  end

  defp socket do
    %Phoenix.LiveView.Socket{
      router: DawarichWeb.Router,
      view: DawarichWeb.SettingsLive.BackgroundJobs,
      endpoint: Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_user: Accounts.get(10001), flash: %{}},
      private: %{
        connect_info: %{session: %{"rails_user_id" => 10001}},
        lifecycle: %Phoenix.LiveView.Lifecycle{}
      }
    }
  end

  defp render_health(socket) do
    socket.assigns
    |> DawarichWeb.SettingsLive.BackgroundJobs.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp request(method, path, id, credentials \\ nil) do
    request = signed(method, path, id)

    request =
      if credentials,
        do: put_req_header(request, "authorization", "Basic " <> Base.encode64(credentials)),
        else: request

    Endpoint.call(request, Endpoint.init([]))
  end

  defp signed(method, path, nil), do: conn(method, path)

  defp signed(method, path, id),
    do:
      put_req_cookie(
        conn(method, path),
        "_dawarich_session",
        RailsUser.cookie(RailsUser.session(id))
      )
end
