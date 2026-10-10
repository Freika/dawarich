defmodule DawarichWeb.A12f3bN04Test do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Settings}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

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
    RailsUser.insert!(%{id: 73401, admin: true, email: "n04@test", settings: %{"keep" => 7}})

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
      result = Settings.verify_supporter(scope(), params)

      if String.trim(name) == "Supported",
        do: assert({:ok, %{"supporter" => true, "platform" => "github"}} = result),
        else: refute(match?({:ok, %{"supporter" => true}}, result))

      assert Accounts.settings(73401)["keep"] == 7
    end

    assert Accounts.settings(73401)["supporter_github_username"] == "Supported"
    assert_received {:verification, %{"github_username" => "supported"}}

    assert rows("SELECT result FROM phoenix.supporter_checks WHERE cache_key=$1", [
             "dawarich/supporter_gh:supported"
           ]) == [[%{"supporter" => true, "platform" => "github"}]]
  end

  @tag a12f3b_case: "N04b"
  test "Cloud test email refusal and a self-hosted queue failure both answer with an alert" do
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

    assert {:alert, _} = Settings.send_test_email(scope(), env: env, self_hosted: false)

    assert {:alert, _} =
             Settings.send_test_email(scope(),
               env: env,
               self_hosted: true,
               oban: :nonexistent_n04
             )
  end

  defp scope, do: Scope.for_user(Accounts.get(73401), "en")
end
