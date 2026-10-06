defmodule DawarichWeb.A12f3bN04Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsCsrf, SettingsSupporterActions, TestEmail}

  defmodule Verify do
    import Plug.Conn
    def init(test), do: test

    def call(conn, test) do
      conn = fetch_query_params(conn)
      send(test, {:verification, conn.query_params})

      case conn.query_params["github_username"] do
        "supported" ->
          send_resp(conn, 200, Jason.encode!(%{supporter: true, platform: "github"}))

        "truthy" ->
          send_resp(conn, 200, Jason.encode!(%{supporter: "yes", platform: "github"}))

        "invalid" ->
          send_resp(conn, 200, "invalid")

        _ ->
          send_resp(conn, 403, "denied")
      end
    end
  end

  setup do
    RailsUser.insert!(%{id: 73401, email: "n04@test", settings: %{"keep" => 7}})

    server =
      start_supervised!(
        {Bandit, plug: {Verify, self()}, port: 0, ip: {127, 0, 0, 1}, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    previous =
      for key <- [:supporter_verify_url, :jobs_repo],
          into: %{},
          do: {key, Application.get_env(:dawarich, key)}

    Application.put_env(:dawarich, :supporter_verify_url, "http://127.0.0.1:#{port}/verify")
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      for {key, value} <- previous, do: Application.put_env(:dawarich, key, value)
    end)

    :ok
  end

  @tag a12f3b_case: "N04a"
  test "supporter verification preserves provider outcomes and flags" do
    for name <- ["", "denied", "invalid", "truthy", " Supported "] do
      params = %{"supporter_github_username" => name}
      conn = apply(SettingsSupporterActions, :call, [request(params), :verify])
      assert conn.status == 302
      flashes = conn.private.dawarich_rails_session_changes["flash"]["flashes"]

      if String.trim(name) == "Supported" do
        assert flashes["notice"] =~ "Github"
      else
        assert flashes["alert"]
      end

      assert Accounts.settings(73401)["keep"] == 7
    end

    assert Accounts.settings(73401)["supporter_github_username"] == "Supported"
    assert_received {:verification, %{"github_username" => "supported"}}

    assert rows("SELECT result FROM phoenix.supporter_checks WHERE cache_key=$1", [
             "dawarich/supporter_gh:supported"
           ]) == [[%{"supporter" => true, "platform" => "github"}]]
  end

  @tag a12f3b_case: "N04b"
  test "Cloud test email refusal is native and self hosted queue failure preserves response" do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    env = %{
      "SMTP_SERVER" => "synthetic.test",
      "SMTP_AUTHENTICATION" => "none",
      "SMTP_STARTTLS" => "false"
    }

    conn = email_request()
    result = TestEmail.call(conn, context: %{self_hosted: false, oidc: false, env: env})
    assert result.status == 303
    assert get_resp_header(result, "location") == ["http://www.example.com/"]
    assert result.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"]

    failed =
      TestEmail.call(email_request(),
        context: %{self_hosted: true, oidc: false, env: env},
        oban: :nonexistent_n04
      )

    assert failed.status == 302
    assert failed.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"]
    refute failed.private.dawarich_rails_session_changes["flash"]["flashes"]["notice"]
  end

  defp request(params) do
    session = RailsUser.session(73401)

    Plug.Test.conn(:post, "/settings/general/verify_supporter")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(:api_params, Map.put(params, "authenticity_token", RailsCsrf.masked_token(session)))
    |> assign(:api_query, %{})
    |> assign(:rails_session, session)
    |> assign(:current_user, Accounts.get(73401))
  end

  defp email_request do
    session = RailsUser.session(73401)
    body = URI.encode_query(%{"authenticity_token" => RailsCsrf.masked_token(session)})

    Plug.Test.conn(:post, "/settings/general/test_email", body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", "#{byte_size(body)}")
    |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
  end
end
