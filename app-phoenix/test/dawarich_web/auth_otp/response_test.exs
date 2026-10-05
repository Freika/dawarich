defmodule DawarichWeb.AuthOtp.ResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import ExUnit.CaptureLog
  alias Dawarich.Auth.{Otp.Pending, SessionCookie}
  alias Dawarich.{RailsCookies, Repo, Test.ParityHTML, Test.RailsUser}
  alias DawarichWeb.AuthOtp.Response
  @secret "a11d-response-synthetic-cookie-key"
  @now ~U[2026-10-04 12:00:00.000000Z]
  @source "test/fixtures/auth/otp/requests.json" |> File.read!() |> Jason.decode!()
  @credentials "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @id 75_530

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    RailsUser.insert!(%{
      id: @id,
      email: "a11d-response@dawarich.test",
      api_key: "A11D_RESPONSE",
      encrypted_password: @credentials["login"]["user"]["encrypted_password"],
      settings: %{}
    })

    %{context: %{secret: @secret, clock: fn -> @now end}}
  end

  defp request(session, path \\ "/users/sign_in") do
    Phoenix.ConnTest.build_conn(:post, path)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> assign(:rails_session, session)
    |> assign(:current_user, nil)
    |> assign(:rails_locked, nil)
  end

  defp decoded(conn) do
    case conn.resp_cookies["_dawarich_session"] do
      nil ->
        %{}

      %{value: value} ->
        {:ok, session} = RailsCookies.decrypt(value, "_dawarich_session", @secret, @now)
        session
    end
  end

  defp headers(conn, row) do
    for {key, expected} <- row["headers"],
        do: assert(get_resp_header(conn, key) == [expected], key)

    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-otp"]
    assert conn.resp_cookies["_dawarich_session"].http_only == true
    assert conn.resp_cookies["_dawarich_session"].same_site == "Lax"
    assert conn.resp_cookies["_dawarich_session"].secure == false
  end

  test "OTP responses persist pending cookies at 422 and complete with source 302", c do
    assert Code.ensure_loaded?(Response)
    user = Repo.get!(Dawarich.Auth.Account, @id)

    log =
      capture_log(fn ->
        for locale <- ~w(en de es fr pl ca zh) do
          {before, _} =
            SessionCookie.for_form(
              %{"locale" => locale, "otp_failed_attempts" => 2, "user_return_to" => "/trips"},
              @secret
            )

          pending = Pending.start(before, @id, "1", DateTime.to_unix(@now))
          response = Response.form(request(before), pending, c.context)
          decoded = decoded(response)
          assert decoded["otp_user_id"] == @id
          assert decoded["otp_challenge_at"] == DateTime.to_unix(@now)
          assert decoded["otp_remember_me"] == true and decoded["otp_failed_attempts"] == 2
          assert decoded["session_id"] == before["session_id"]
          csrf_same = decoded["_csrf_token"] == before["_csrf_token"]
          assert csrf_same
          assert decoded["locale"] == locale
          assert response.status == 422 and response.halted
          row = @source["start_#{locale}"]
          headers(response, row)

          assert ParityHTML.fragment(response.resp_body, ".hero") ==
                   ParityHTML.normalize(File.read!("test/fixtures/auth/otp/challenge_en.html"))

          title =
            response.resp_body
            |> LazyHTML.from_document()
            |> LazyHTML.query("title")
            |> LazyHTML.text()

          assert title == row["document_title"]

          for remember <- [
                nil,
                [
                  [@id],
                  binary_part(user.encrypted_password, 0, 29),
                  Dawarich.Accounts.remember_generated_at(@now)
                ]
              ] do
            result = %{user: user, session: Pending.clear(pending), remember: remember}

            completed =
              Response.signed_in(request(pending, "/users/otp_challenge"), result, c.context)

            session = decoded(completed)
            assert completed.status == 302 and completed.halted
            assert get_resp_header(completed, "location") == ["http://www.example.com/trips"]
            assert session["session_id"] != pending["session_id"]

            assert Map.keys(session) --
                     ~w(session_id locale _csrf_token flash warden.user.user.key) == []

            notice =
              DawarichWeb.Translate.t(
                locale,
                "controllers.users.otp_challenge.signed_in_successfully",
                %{}
              )

            assert session["flash"]["flashes"] == %{"notice" => notice}
            headers(completed, @source["totp"])

            if remember do
              remembered =
                RailsCookies.verify(
                  completed.resp_cookies["remember_user_token"].value,
                  "remember_user_token",
                  @secret,
                  @now
                ) == {:ok, remember}

              assert remembered

              assert completed.resp_cookies["remember_user_token"].max_age ==
                       Dawarich.Accounts.remember_for()
            else
              refute Map.has_key?(completed.resp_cookies, "remember_user_token")
            end
          end

          expired =
            Response.expired(
              request(pending, "/users/otp_challenge"),
              Pending.clear(pending),
              c.context
            )

          assert expired.status == 302
          assert get_resp_header(expired, "location") == ["http://www.example.com/users/sign_in"]

          assert Map.keys(decoded(expired)) --
                   ~w(session_id locale _csrf_token user_return_to flash) == []

          assert map_size(decoded(expired)["flash"]["flashes"]) == 1
          headers(expired, @source["ttl_300"])
        end
      end)

    refute log =~ "a11d-response-synthetic-cookie-key"
    refute log =~ "A11D_RESPONSE"
  end
end
