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
    assert AdminGate.background?(signed(:get, "/settings/background_jobs", 10001), %{})
    refute AdminGate.background?(signed(:get, "/settings/background_jobs", 10002), %{})
    assert request(:get, "/settings/background_jobs", 10001).status == 200

    session = %{
      "rails_user_id" => 10001,
      "locale" => "en",
      "self_hosted" => false,
      "request_path" => "/settings/background_jobs",
      "query_params" => %{},
      "rails_csrf_token" => "CSRF",
      "base_url" => "http://localhost"
    }

    socket = %Phoenix.LiveView.Socket{
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

    assert {:cont, mounted} = AdminLiveAuth.on_mount(:background, %{}, session, socket)
    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)
    assert {:halt, _} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, mounted)
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
