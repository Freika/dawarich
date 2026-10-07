defmodule DawarichWeb.StandaloneAuthPagesTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Auth.{Account, TwoFactor.Secret, TwoFactor.Totp}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @protected_routes ~w(
    /achievements /achievements/:key /settings/users/export /insights/details
    /imports/:id/download /imports/:id /imports/:id/edit /trips /trips/new
    /trips/:id/edit /trips/:id /places /points /tags /tags/new /tags/:id/edit
    /settings/visits /family /family/new /family/edit /family/invitations
    /family/location_requests/:id /admin/settings /settings/users
    /settings/users/:id /settings/users/:id/edit /settings/background_jobs
    /trial/upgrade /trial/resume /map/timeline_feeds /map/timeline_feeds/calendar
    /map/residency /map/timeline_feeds/:id/track_info /places/nearby /places/:id
    /tracks/:track_id/segments /points/:id/address /share_links/hub /share_links/live/new
    /trips/:trip_id/share_link/new /tracks/:track_id/share_link/new /share_links/timeline/new
  )
  @otp_env %{
    "OTP_ENCRYPTION_PRIMARY_KEY" => "standalone-pages-synthetic-primary",
    "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "standalone-pages-synthetic-deterministic",
    "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "standalone-pages-synthetic-salt"
  }

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Dawarich.State.put_registration_enabled(Repo, false)

    env =
      Map.merge(@otp_env, %{
        "DAWARICH_RAILS" => "off",
        "SELF_HOSTED" => "true",
        "FORCE_SSL" => "false",
        "JWT_SECRET_KEY" => "standalone-pages-synthetic-jwt-not-for-production"
      })

    previous = Map.new(env, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(env)

    on_exit(fn ->
      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    hash = Bcrypt.hash_pwd_salt("standalone-pages-password", log_rounds: 4)

    actors =
      for admin <- [false, true] do
        RailsUser.insert!(%{
          id: System.unique_integer([:positive]),
          email: "standalone-pages-#{admin}@example.test",
          encrypted_password: hash,
          api_key: "standalone-pages-#{admin}-synthetic",
          admin: admin,
          provider: "github",
          settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
        })
      end

    %{actors: actors}
  end

  @tag :sa_pages_anonymous
  test "standalone anonymous protected pages redirect with Rails flash and return path", c do
    for path <- protected_paths(hd(c.actors).id) ++ ["/settings/two_factor"] do
      assert_sign_in(page(%{}, path), path)
    end

    for {method, path} <- [
          {:post, "/settings/two_factor"},
          {:post, "/settings/two_factor/verify"},
          {:delete, "/settings/two_factor"}
        ] do
      assert_sign_in(request(%{}, method, path, ""), path)
    end
  end

  @tag :sa_pages_pending
  test "standalone two factor pending sessions cannot enter protected pages or manage OTP", c do
    for actor <- c.actors do
      pending = %{
        "otp_user_id" => actor.id,
        "otp_challenge_at" => DateTime.to_unix(DateTime.utc_now()),
        "_csrf_token" => DawarichWeb.RailsCsrf.new_token()
      }

      for path <- protected_paths(actor.id) ++ ["/settings/two_factor"] do
        assert_sign_in(page(pending, path), path)
      end

      for {method, path} <- [
            {:post, "/settings/two_factor"},
            {:post, "/settings/two_factor/verify"},
            {:delete, "/settings/two_factor"}
          ] do
        assert_sign_in(request(pending, method, path, ""), path)
      end

      refute Repo.get!(Account, actor.id).otp_required_for_login
      assert Repo.get!(Account, actor.id).otp_secret == nil
    end
  end

  @tag :sa_pages_roles
  test "standalone page admission preserves admin refusal and ordinary user background access",
       c do
    [user, admin] = c.actors

    for path <- user_paths(admin.id) do
      denied = page(session(user), path)
      assert denied.status == 303
      assert denied.resp_body == ""
      assert get_resp_header(denied, "location") == ["http://www.example.com/"]

      assert RailsFormRequests.rails_session(denied)["flash"]["flashes"] == %{
               "alert" => "You are not authorized to perform this action."
             }

      referred =
        page(session(user), path, [{"referer", "http://www.example.com/settings/general"}])

      assert get_resp_header(referred, "location") == ["http://www.example.com/settings/general"]
      admitted = page(session(admin), path)
      assert admitted.status == 200
      assert admitted.resp_body =~ "data-phx-main"
    end

    translated = page(session(user), "/settings/users?locale=de")
    assert translated.status == 303

    assert RailsFormRequests.rails_session(translated)["flash"]["flashes"] == %{
             "alert" => "Du bist nicht berechtigt, diese Aktion auszuführen."
           }

    for actor <- c.actors,
        path <- ["/settings/background_jobs", "/achievements", "/achievements/country_de"] do
      admitted = page(session(actor), path)
      assert admitted.status == 200
      assert admitted.resp_body =~ "data-phx-main"
    end
  end

  @tag :sa_pages_two_factor
  test "standalone two factor management renders verify and backup codes and disables for either role",
       c do
    System.put_env("SELF_HOSTED", "false")

    for actor <- c.actors do
      session = session(actor)
      cookie = "_dawarich_session=" <> RailsUser.cookie(session)

      ambiguous =
        build_conn()
        |> put_req_header("cookie", cookie <> "; " <> cookie)
        |> get("/settings/two_factor")

      assert ambiguous.status == 422
      shown = page(session, "/settings/two_factor")
      assert shown.status == 200
      assert get_resp_header(shown, "x-dawarich-auth-owner") == ["native-two-factor"]
      session = RailsFormRequests.rails_session(shown)
      setup = form(session, "/settings/two_factor", %{})
      assert setup.status == 200
      assert setup.resp_body =~ "action=\"/settings/two_factor/verify\""
      session = RailsFormRequests.rails_session(setup)

      csrf_rejected =
        RailsFormRequests.post_form(
          session,
          "authenticity_token=invalid&otp_attempt=000000",
          [{"accept", "text/html"}],
          "/settings/two_factor/verify"
        )

      assert csrf_rejected.status == 422
      refute Repo.get!(Account, actor.id).otp_required_for_login
      account = Repo.get!(Account, actor.id)
      {:ok, secret} = Secret.decrypt(account.otp_secret, @otp_env)
      code = Totp.at(secret, DateTime.to_unix(DateTime.utc_now()))
      invalid = form(session, "/settings/two_factor/verify", %{"otp_attempt" => "invalid"})
      assert invalid.status == 422
      assert invalid.resp_body =~ "Invalid verification code"
      refute Repo.get!(Account, actor.id).otp_required_for_login
      verified = form(session, "/settings/two_factor/verify", %{"otp_attempt" => code})
      assert verified.status == 200

      codes =
        verified.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("code")
        |> LazyHTML.to_tree()
        |> Enum.map(fn {_, _, text} -> IO.iodata_to_binary(text) end)

      assert length(codes) == 10
      assert Repo.get!(Account, actor.id).otp_required_for_login
      assert length(Repo.get!(Account, actor.id).otp_backup_codes) == 10
      session = RailsFormRequests.rails_session(verified)

      disabled =
        form(session, "/settings/two_factor", %{
          "_method" => "delete",
          "password" => "standalone-pages-password",
          "otp_attempt" => hd(codes)
        })

      assert disabled.status == 302
      assert disabled.resp_body == ""

      assert get_resp_header(disabled, "location") == [
               "http://www.example.com/settings/two_factor"
             ]

      assert RailsFormRequests.rails_session(disabled)["flash"]["flashes"] == %{
               "notice" => "Two-factor authentication disabled."
             }

      account = Repo.get!(Account, actor.id)
      refute account.otp_required_for_login
      assert account.otp_secret == nil and account.otp_backup_codes == nil
    end
  end

  defp user_paths(id),
    do: ["/settings/users", "/settings/users/#{id}", "/settings/users/#{id}/edit"]

  defp protected_paths(id),
    do:
      Enum.map(
        @protected_routes,
        &String.replace(&1, ~r/:[a-z_]+/, fn
          ":key" -> "country_de"
          _ -> to_string(id)
        end)
      )

  defp session(actor),
    do:
      Map.put(RailsUser.session(actor.id), "warden.user.user.key", [
        [actor.id],
        binary_part(actor.encrypted_password, 0, 29)
      ])

  defp page(session, path, headers \\ []), do: request(session, :get, path, "", headers)

  defp request(session, method, path, body, headers \\ []) do
    conn =
      Enum.reduce(headers, build_conn(), fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    conn =
      if method == :get,
        do: conn,
        else: put_req_header(conn, "content-type", "application/x-www-form-urlencoded")

    conn
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
    |> dispatch(@endpoint, method, path, if(method == :get, do: nil, else: body))
  end

  defp form(session, path, fields) do
    fields
    |> Map.put("authenticity_token", DawarichWeb.RailsCsrf.masked_token(session))
    |> URI.encode_query()
    |> then(&RailsFormRequests.post_form(session, &1, [{"accept", "text/html"}], path))
  end

  defp assert_sign_in(conn, path) do
    assert conn.status == 302
    assert conn.resp_body == ""
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
    session = RailsFormRequests.rails_session(conn)
    assert session["user_return_to"] == path

    assert session["flash"]["flashes"] == %{
             "alert" => "You need to sign in or sign up before continuing."
           }

    refute conn.assigns[:current_user]
  end
end
