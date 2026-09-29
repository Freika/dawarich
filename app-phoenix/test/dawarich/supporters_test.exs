defmodule Dawarich.SupportersTest do
  use Dawarich.JobsCase

  alias Dawarich.{AppVersion, Supporters}

  defmodule Verify do
    import Plug.Conn

    def init(test), do: test

    def call(conn, test) do
      conn = fetch_query_params(conn)
      send(test, {:verify, conn.query_params, get_req_header(conn, "x-dawarich-version")})

      supporter =
        conn.query_params["github_username"] == "freika" or
          conn.query_params["email_hash"] ==
            "46f1e0f1e957b037fb14d91253df98648c11107312076fa1eeced218223fdd26"

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{supporter: supporter}))
    end
  end

  setup do
    server =
      start_supervised!(
        {Bandit, plug: {Verify, self()}, port: 0, ip: {127, 0, 0, 1}, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    previous = Application.get_env(:dawarich, :supporter_verify_url)

    Application.put_env(
      :dawarich,
      :supporter_verify_url,
      "http://127.0.0.1:#{port}/api/v1/verify"
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :supporter_verify_url, previous),
        else: Application.delete_env(:dawarich, :supporter_verify_url)
    end)
  end

  test "email first, then GitHub, with the app version, cached for a day" do
    now = DateTime.utc_now()

    settings = %{
      "supporter_email" => " Fan@Example.com ",
      "supporter_github_username" => " Freika "
    }

    assert Supporters.badge?(settings, now)
    hash = Base.encode16(:crypto.hash(:sha256, "fan@example.com"), case: :lower)
    assert_received {:verify, %{"email_hash" => ^hash}, [version]}
    assert version == AppVersion.current()
    assert_received {:verify, %{"github_username" => "freika"}, _}

    assert Supporters.badge?(settings, now)
    refute_received {:verify, _, _}
    assert Supporters.badge?(settings, DateTime.add(now, 86_401))
    assert_received {:verify, _, _}
  end

  test "a verified email short-circuits GitHub verification" do
    now = DateTime.utc_now()

    settings = %{
      "supporter_email" => "verified@example.com",
      "supporter_github_username" => "freika"
    }

    assert Supporters.badge?(settings, now)
    assert_received {:verify, %{"email_hash" => _}, _}
    refute_received {:verify, %{"github_username" => _}, _}
  end

  test "the badge setting is honoured before any request" do
    refute Supporters.badge?(
             %{"supporter_github_username" => "freika", "show_supporter_badge" => "false"},
             DateTime.utc_now()
           )

    refute Supporters.badge?(
             %{"supporter_github_username" => "freika", "show_supporter_badge" => ""},
             DateTime.utc_now()
           )

    refute_received {:verify, _, _}
    refute Supporters.badge?(%{}, DateTime.utc_now())
  end
end
