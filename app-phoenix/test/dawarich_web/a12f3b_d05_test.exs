defmodule DawarichWeb.A12f3bD05Test do
  use Dawarich.JobsCase, async: false
  import Plug.Conn
  alias Dawarich.{RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{HomeGate, TrialWelcome, WelcomeGate}
  @now ~U[2026-10-04 10:00:00Z]
  @jwt "synthetic-trialhome-welcome"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    saved = Map.new(~w(DAWARICH_RAILS SELF_HOSTED), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "false")

    RailsUser.insert!(
      %{id: 18051, email: "welcome@example.invalid", status: 2},
      Dawarich.ScratchRepo
    )

    RailsUser.insert!(%{
      id: 18051,
      email: "welcome@example.invalid",
      status: 2,
      settings: %{"timezone" => "Europe/Berlin"}
    })

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    %{
      context: %{
        secret: RailsSecret.fetch(),
        jwt_secret: @jwt,
        env: %{},
        oidc: false,
        clock: fn -> @now end,
        repo: Dawarich.ScratchRepo
      }
    }
  end

  @tag a12f3b_case: "D05a"
  test "welcome and home own referral mobile and legacy session branches", c do
    root = Plug.Test.conn(:get, "/?client=ios&aff=partner&via=ignored")
    assert HomeGate.owned?(root, %{})

    for mode <- ~w(true false) do
      System.put_env("SELF_HOSTED", mode)
      Dawarich.State.put_registration_enabled(Repo, true)

      home =
        Phoenix.ConnTest.dispatch(
          Phoenix.ConnTest.build_conn(),
          DawarichWeb.Endpoint,
          :get,
          "/?client=ios&aff=partner&via=ignored",
          nil
        )

      assert home.status == 200

      {:ok, stored} =
        RailsCookies.decrypt(
          home.resp_cookies["_dawarich_session"].value,
          "_dawarich_session",
          RailsSecret.fetch(),
          DateTime.utc_now()
        )

      assert stored["dawarich_client"] == "ios"
      assert stored["partnero_referral"] == if(mode == "false", do: "partner", else: nil)

      head =
        Phoenix.ConnTest.dispatch(
          Phoenix.ConnTest.build_conn(),
          DawarichWeb.Endpoint,
          :head,
          "/",
          nil
        )

      assert head.status == 200 and head.resp_body == ""

      Repo.query!("UPDATE users SET settings=$1 WHERE id=18051", [%{}], log: false)

      member =
        Phoenix.ConnTest.dispatch(
          RailsUser.signed_in(18051, %{"dawarich_client" => "ios"}),
          DawarichWeb.Endpoint,
          :get,
          "/?client=android",
          nil
        )

      assert get_resp_header(member, "location") == ["http://www.example.com/map/v2"]
    end

    bad = request("bad-signature", %{}, %{}, "wrong-signature")
    invalid = TrialWelcome.call(bad, context: c.context)
    assert invalid.status == 302
    refute claimed?("bad-signature")
    assert count() == 0

    conn =
      request("welcome", %{
        "dawarich_client" => "ios",
        "partnero_referral" => "partner",
        "devise.return_to" => "/"
      })

    assert WelcomeGate.owned?(conn, %{}, context: c.context)
    result = TrialWelcome.call(conn, context: c.context)
    assert result.status == 302
    assert get_resp_header(result, "location") == ["http://www.example.com/map/v2"]

    {:ok, session} =
      RailsCookies.decrypt(
        result.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        @now
      )

    assert session["dawarich_client"] == "ios" and session["partnero_referral"] == "partner"
    assert session["warden.user.user.key"] |> hd() == [18051]
    assert session["flash"]["flashes"]["notice"] != nil
    replay = TrialWelcome.call(conn, context: c.context)
    assert get_resp_header(replay, "location") == ["http://www.example.com/users/sign_in"]
    assert count() == 1
    marked = request("query-markers", %{})

    marked = %{
      marked
      | query_string: marked.query_string <> "&client=android&aff=new-partner&locale=de"
    }

    assert WelcomeGate.owned?(marked, %{}, context: c.context)
    marked = TrialWelcome.call(marked, context: c.context)
    assert marked.status == 302

    {:ok, marked_session} =
      RailsCookies.decrypt(
        marked.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        @now
      )

    assert marked_session["dawarich_client"] == "android"
    assert marked_session["partnero_referral"] == "new-partner"
    assert marked_session["locale"] == "de"

    expired =
      request("expired", %{}, %{"exp" => DateTime.to_unix(@now)})
      |> TrialWelcome.call(context: c.context)

    assert get_resp_header(expired, "location") == ["http://www.example.com/users/sign_in"]
    refute claimed?("expired")

    unsupported =
      Plug.Test.conn(:get, "/trial/welcome?format=json") |> TrialWelcome.call(context: c.context)

    assert unsupported.status == 422 and unsupported.halted
    assert get_resp_header(unsupported, "x-dawarich-rails-proxy") == []
  end

  @tag a12f3b_case: "D05b"
  test "home never proxies after native welcome or session effect", c do
    server = Dawarich.Test.RawHTTP.listen()
    old = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, old)
      :gen_tcp.close(server.listen)
    end)

    parent = self()

    start_supervised!(
      {Task,
       fn ->
         socket = Dawarich.Test.RawHTTP.accept(server)
         Dawarich.Test.RawHTTP.read_head(socket)
         send(parent, :replayed)

         Dawarich.Test.RawHTTP.reply(
           socket,
           "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
         )

         :gen_tcp.close(socket)
       end}
    )

    conn =
      request("response-failure", %{})
      |> register_before_send(fn conn ->
        if Process.get(:welcome_response_failed) do
          conn
        else
          Process.put(:welcome_response_failed, true)
          raise "deterministic response failure"
        end
      end)

    result = TrialWelcome.call(conn, context: c.context)
    assert result.status == 500 and result.halted
    assert result.resp_cookies == %{}
    assert claimed?("response-failure")
    assert count() == 1
    refute_receive :replayed
    replay = TrialWelcome.call(request("response-failure", %{}), context: c.context)
    assert get_resp_header(replay, "location") == ["http://www.example.com/users/sign_in"]
    assert count() == 1
    System.put_env("SELF_HOSTED", "true")
    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)

    root =
      Phoenix.ConnTest.dispatch(
        Phoenix.ConnTest.build_conn(),
        DawarichWeb.Endpoint,
        :get,
        "/?client=android",
        nil
      )

    assert root.status == 503 and root.halted
    assert get_resp_header(root, "x-dawarich-rails-proxy") == []
    refute_receive :replayed
  end

  defp request(jti, session, extra \\ %{}, secret \\ @jwt) do
    claims =
      Map.merge(
        %{
          "purpose" => "trial_welcome",
          "user_id" => 18051,
          "exp" => DateTime.to_unix(@now) + 1800,
          "jti" => jti
        },
        extra
      )

    input =
      Base.url_encode64(~s({"alg":"HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(claims), padding: false)

    token =
      input <>
        "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, secret, input), padding: false)

    Plug.Test.conn(:get, "/trial/welcome?" <> URI.encode_query(%{"token" => token}))
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
  end

  defp count,
    do:
      Dawarich.ScratchRepo.query!("SELECT sign_in_count FROM users WHERE id=18051", [],
        log: false
      ).rows
      |> hd()
      |> hd()

  defp claimed?(jti) do
    key =
      "trial_welcome:consumed:sha256:" <> Base.encode16(:crypto.hash(:sha256, jti), case: :lower)

    Dawarich.ScratchRepo.query!("SELECT count(*) FROM phoenix.once_claims WHERE key=$1", [key],
      log: false
    ).rows == [[1]]
  end
end
