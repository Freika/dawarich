defmodule DawarichWeb.AuthAccount.ResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, RailsCookies, Repo}
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.AuthAccount.Response

  @secret "a11rest-response-cookie-secret-not-for-production"
  @rows File.read!("test/fixtures/auth/account/requests.json") |> Jason.decode!()

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
  end

  test "account responses preserve source status redirect flash and headers" do
    assert Code.ensure_loaded?(Response), "account response module must exist"
    row = Enum.find(@rows, &(&1["name"] == "multiple_errors"))

    RailsUser.insert!(%{
      id: 73423,
      email: row["email"],
      api_key: "API_KEY",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    user = Accounts.get(73423)

    {session, _} =
      SessionCookie.for_form(
        %{
          "user_return_to" => "/stats",
          "locale" => "en",
          "a11rest" => "retained",
          "devise.test" => "expire"
        },
        @secret
      )

    session =
      Map.put(session, "warden.user.user.key", [
        [user.id],
        binary_part(user.encrypted_password, 0, 29)
      ])

    context = %{secret: @secret}

    errors = [
      {:email, :invalid, %{}},
      {:password_confirmation, :confirmation, %{}},
      {:password, :too_short, %{"count" => 12}},
      {:current_password, :blank, %{}}
    ]

    render = %{email: row["submitted_email"], errors: errors}

    log =
      capture_log(fn ->
        failure = Response.form(request(session, user), user, render, context)
        assert failure.status == row["status"]
        assert failure.halted
        assert get_resp_header(failure, "x-dawarich-auth-owner") == ["native-account"]
        assert get_resp_header(failure, "content-type") == ["text/html; charset=utf-8"]
        assert get_resp_header(failure, "x-frame-options") == ["SAMEORIGIN"]

        assert ParityHTML.fragment(failure.resp_body, "div.w-full.min-w-0.my-5") ==
                 ParityHTML.normalize(
                   File.read!("test/fixtures/auth/account/multiple_errors_en.html")
                 )

        assert length(
                 LazyHTML.from_document(failure.resp_body)
                 |> LazyHTML.query("input[type=password][value]")
                 |> LazyHTML.to_tree()
               ) == 0

        cookie = failure.resp_cookies["_dawarich_session"]

        assert cookie.http_only and cookie.same_site == "Lax" and cookie.path == "/" and
                 not cookie.secure

        assert decrypted?(cookie.value, session)
        assert failure.assigns.current_user.id == user.id
        assert failure.private.dawarich_rails_user.id == user.id

        changed = %{
          user
          | encrypted_password: "$2a$04$" <> String.duplicate("N", 53),
            email: "updated@dawarich.test"
        }

        success = Response.updated(request(session, user), changed, context)
        oracle = Enum.find(@rows, &(&1["name"] == "both"))
        assert success.status == oracle["status"]
        assert success.resp_body == "" and success.halted
        assert get_resp_header(success, "location") == [oracle["location"]]
        assert get_resp_header(success, "x-dawarich-auth-owner") == ["native-account"]
        assert success.assigns.rails_session["flash"]["flashes"] == oracle["session"]["flash"]

        assert success.assigns.rails_session["warden.user.user.key"] == [
                 [changed.id],
                 binary_part(changed.encrypted_password, 0, 29)
               ]

        assert success.assigns.rails_session["_csrf_token"] == session["_csrf_token"]
        assert success.assigns.rails_session["user_return_to"] == "/stats"
        assert success.assigns.current_user == changed
        assert success.private.dawarich_rails_user == changed

        assert decrypted?(
                 success.resp_cookies["_dawarich_session"].value,
                 success.assigns.rails_session
               )

        assert Map.keys(success.resp_cookies) == ["_dawarich_session"]

        assert_raise DawarichWeb.RailsSession.Overflow, fn ->
          request(Map.put(session, "huge", String.duplicate("x", 6000)), user)
          |> Response.updated(changed, context)
        end

        assert_raise DawarichWeb.RailsSession.Overflow, fn ->
          request(Map.put(session, "huge", String.duplicate("x", 6000)), user)
          |> Response.form(user, render, context)
        end
      end)

    assert log == ""
  end

  defp request(session, user) do
    Plug.Test.conn("PUT", "http://www.example.com/users")
    |> assign(:rails_session, session)
    |> assign(:current_user, user)
  end

  defp decrypted?(cookie, session),
    do:
      RailsCookies.decrypt(cookie, "_dawarich_session", @secret, DateTime.utc_now()) ==
        {:ok, session}
end
