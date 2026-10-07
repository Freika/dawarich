defmodule Dawarich.A12f3bH01Hot5Test do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{Endpoint, RailsCsrf, Router}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    saved = Map.new(~w(DAWARICH_RAILS SELF_HOSTED JWT_SECRET_KEY), &{&1, System.get_env(&1)})
    context = Application.get_env(:dawarich, :account_destroy_context)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("JWT_SECRET_KEY", "synthetic-hot5-welcome")
    Application.put_env(:dawarich, :account_destroy_context, %{})
    <<a::16, b::16, c::16, d::16, e::16, f::16>> = :crypto.strong_rand_bytes(12)
    Process.put(:hot5_ip, {0x2001, 0xDB8, a, b, c, d, e, f})

    for {id, admin} <- [{35001, true}, {35002, false}, {35003, false}] do
      RailsUser.insert!(%{
        id: id,
        email: "hot5-#{id}@example.invalid",
        admin: admin,
        settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
      })
    end

    Dawarich.State.put_registration_enabled(Repo, true)

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))

      if context,
        do: Application.put_env(:dawarich, :account_destroy_context, context),
        else: Application.delete_env(:dawarich, :account_destroy_context)
    end)

    :ok
  end

  @tag a12f3b_case: "H01d"
  test "mounted admin and trial home routes retain native effects and authorization" do
    for {method, path, plug, pipeline, gate} <- [
          {"DELETE", "/settings/users/35002", DawarichWeb.AdminUserDestroy, [:admin_writes],
           {DawarichWeb.AdminWritesGate, :destroy?}},
          {"POST", "/admin/settings/test_geocoding", DawarichWeb.AdminWrites.Settings,
           [:admin_writes], {DawarichWeb.AdminWritesGate, :test_geocoding?}},
          {"GET", "/", DawarichWeb.HomeDispatch, [:public_home], {DawarichWeb.HomeGate, :owned?}},
          {"GET", "/trial/welcome", DawarichWeb.TrialWelcome, [:trial_welcome],
           {DawarichWeb.WelcomeGate, :owned?}},
          {"GET", "/trial/upgrade", DawarichWeb.TrialUpgrade, [:rails_frame],
           {DawarichWeb.TrialGate, :upgrade?}},
          {"GET", "/trial/resume", Phoenix.LiveView.Plug, [:trial_resume],
           {DawarichWeb.TrialGate, :resume?}}
        ] do
      route = Phoenix.Router.route_info(Router, method, path, "www.example.com")
      assert is_map(route), "missing #{method} #{path}"
      assert route.plug == plug
      assert route.pipe_through == pipeline
      assert route.rails_gate == gate

      assert Enum.count(
               Router.__routes__(),
               &(String.upcase(to_string(&1.verb)) == method and &1.path == route.route)
             ) == 1
    end

    timeout = Repo.query!("SHOW statement_timeout", [], log: false).rows

    for path <- ["/admin/settings", "/settings/users", "/settings/users/35002/edit"] do
      Repo.transaction(fn ->
        Repo.query!("SAVEPOINT hot5_admin_page", [], log: false)

        try do
          assert request(35001, "GET", path).status == 200
        after
          Repo.query!("ROLLBACK TO SAVEPOINT hot5_admin_page", [], log: false)
          Repo.query!("RELEASE SAVEPOINT hot5_admin_page", [], log: false)
        end
      end)
    end

    assert Repo.query!("SHOW statement_timeout", [], log: false).rows == timeout

    assert request(35001, "PATCH", "/admin/settings", %{
             "instance_settings[store_geodata]" => "false"
           }).status == 303

    assert Repo.query!("SELECT value FROM instance_settings WHERE key='store_geodata'").rows == [
             [false]
           ]

    probe = request(35001, "POST", "/admin/settings/test_geocoding")
    assert probe.status == 303
    assert get_resp_header(probe, "location") == ["http://www.example.com/admin/settings"]
    assert probe.private.dawarich_rails_session_changes["flash"]["flashes"] != %{}

    for method <- ["DELETE", "POST"] do
      params = if method == "POST", do: %{"_method" => "delete"}, else: %{}
      assert request(35001, method, "/settings/users/35002", params).status == 503
    end

    assert Accounts.get(35002).deleted_at == nil

    Application.put_env(:dawarich, :account_destroy_context, %{
      enqueue_destroy: fn id ->
        send(self(), {:destroy, id})
        :ok
      end
    })

    for {method, path} <- [
          {"DELETE", "/settings/users/35002"},
          {"POST", "/admin/settings/test_geocoding"}
        ] do
      assert request(35002, method, path).status == 303
      assert request(nil, method, path).status == 302
      assert request(35001, method, path, %{"authenticity_token" => "invalid"}).status == 422
      System.put_env("SELF_HOSTED", "false")
      assert request(35001, method, path).status == 303
      System.put_env("SELF_HOSTED", "true")
      assert Accounts.get(35002).deleted_at == nil
      refute_received {:destroy, _}
    end

    for {method, id, params} <- [
          {"DELETE", 35002, %{}},
          {"POST", 35003, %{"_method" => "delete"}}
        ] do
      result = request(35001, method, "/settings/users/#{id}", params)
      assert result.status == 302
      assert get_resp_header(result, "location") == ["http://www.example.com/settings/users"]

      assert Repo.query!("SELECT deleted_at IS NOT NULL FROM users WHERE id=$1", [id]).rows == [
               [true]
             ]

      assert_received {:destroy, ^id}
    end

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands").rows == [[0]]
    assert_home_and_welcome()
  end

  defp assert_home_and_welcome do
    for mode <- ~w(true false) do
      System.put_env("SELF_HOSTED", mode)
      home = request(nil, "GET", "/?client=ios&aff=partner&via=ignored")
      assert home.status == 200
      head = request(nil, "HEAD", "/")
      assert head.status == home.status and head.resp_body == ""
      assert get_resp_header(head, "content-type") == get_resp_header(home, "content-type")
      stored = session(home)
      assert stored["dawarich_client"] == "ios"
      assert stored["partnero_referral"] == if(mode == "false", do: "partner", else: nil)

      member = request(35001, "GET", "/")
      assert get_resp_header(member, "location") == ["http://www.example.com/map/v2"]
      assert get_resp_header(home, "x-dawarich-rails-proxy") == []
    end

    path =
      "/trial/welcome?" <> URI.encode_query(%{"token" => welcome_token(), "client" => "android"})

    first = request(nil, "GET", path)
    assert first.status == 302
    assert get_resp_header(first, "x-dawarich-trial-owner") == ["native-welcome"]
    assert get_resp_header(first, "location") == ["http://www.example.com/map/v2"]
    stored = session(first)
    assert stored["warden.user.user.key"] |> hd() == [35001]
    assert stored["dawarich_client"] == "android"
    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=35001").rows == [[1]]
    replay = request(nil, "GET", path)
    assert get_resp_header(replay, "location") == ["http://www.example.com/users/sign_in"]
    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=35001").rows == [[1]]
    assert get_resp_header(replay, "x-dawarich-rails-proxy") == []
  end

  defp welcome_token do
    claims = %{
      "purpose" => "trial_welcome",
      "user_id" => 35001,
      "exp" => DateTime.to_unix(DateTime.utc_now()) + 1800,
      "jti" => Ecto.UUID.generate()
    }

    input =
      Base.url_encode64(~s({"alg":"HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(claims), padding: false)

    input <>
      "." <>
      Base.url_encode64(:crypto.mac(:hmac, :sha256, "synthetic-hot5-welcome", input),
        padding: false
      )
  end

  defp session(conn) do
    {:ok, stored} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    stored
  end

  defp request(id, method, path, params \\ %{}) do
    session = if id, do: RailsUser.session(id), else: %{}

    body =
      if method in ~w(GET HEAD),
        do: "",
        else:
          Plug.Conn.Query.encode(
            Map.put_new(params, "authenticity_token", RailsCsrf.masked_token(session))
          )

    Plug.Test.conn(method, path, body)
    |> Map.put(:remote_ip, Process.get(:hot5_ip))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
    |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
    |> Endpoint.call(Endpoint.init([]))
  end
end
