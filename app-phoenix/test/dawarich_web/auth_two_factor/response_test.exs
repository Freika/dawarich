defmodule DawarichWeb.AuthTwoFactor.ResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, RailsCookies, Repo}
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.AuthTwoFactor.{Form, Response}

  @secret "a11c-response-synthetic-cookie-key"
  @root "test/fixtures/auth/two_factor"
  @rows (@root <> "/requests.json") |> File.read!() |> Jason.decode!()

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

  test "Rails failed verification replaces inherited alert in place" do
    row = File.read!(@root <> "/review_inherited_alert.json") |> Jason.decode!()

    RailsUser.insert!(%{
      id: 74501,
      email: "inherited-flash@dawarich.test",
      api_key: "API_KEY",
      settings: %{}
    })

    user = Accounts.get(74501)
    {session, _} = SessionCookie.for_form(%{"locale" => "en"}, @secret)

    session =
      session
      |> Map.put("warden.user.user.key", [[user.id], binary_part(user.encrypted_password, 0, 29)])
      |> Map.put("flash", %{"discard" => [], "flashes" => row["incoming"]})

    otp = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    render = %{
      kind: :verify,
      secret: otp,
      uri: Dawarich.Auth.TwoFactor.Totp.provisioning_uri(otp, user.email),
      user: %{otp_required_for_login: false},
      reason: :invalid_verification_code
    }

    response =
      Response.form(
        request(session, user, "POST", "/settings/two_factor/verify"),
        user,
        render,
        row["status"],
        %{secret: @secret}
      )

    assert response.status == 422
    expected = Enum.map(row["flash_entries"], fn [key, value] -> {key, value} end)
    assert response.assigns.flash_messages == expected
    refute response.resp_body =~ row["incoming"]["alert"]
    message = expected |> List.keyfind("alert", 0) |> elem(1)
    assert length(String.split(response.resp_body, message)) == 2
    page = File.read!(@root <> "/review/inherited_alert.html")

    assert ParityHTML.fragment(response.resp_body, "#flash-messages") ==
             ParityHTML.normalize(page)
  end

  test "management render and redirects preserve Rails identity and flash semantics" do
    RailsUser.insert!(%{
      id: 74500,
      email: "response@dawarich.test",
      api_key: "API_KEY",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    user = Accounts.get(74500)

    {session, _} =
      SessionCookie.for_form(
        %{
          "user_return_to" => "/stats",
          "locale" => "en",
          "a11c" => "retain",
          "devise.test" => "retain"
        },
        @secret
      )

    session =
      Map.put(session, "warden.user.user.key", [
        [user.id],
        binary_part(user.encrypted_password, 0, 29)
      ])

    context = %{secret: @secret}

    log =
      capture_log(fn ->
        for name <-
              ~w(disabled enabled setup verify_bad verify_good disabled_de enabled_de setup_de verify_bad_de verify_good_de) ++
                for(
                  locale <- ~w(es fr pl ca zh),
                  name <- ~w(disabled enabled setup verify_bad verify_good),
                  do: name <> "_" <> locale
                ) do
          row = Enum.find(@rows, &(&1["name"] == name))
          page = File.read!(@root <> "/" <> name <> ".html")
          doc = LazyHTML.from_fragment(page)
          secret = doc |> LazyHTML.query("details code") |> LazyHTML.text()

          codes =
            doc
            |> LazyHTML.query("code.font-mono")
            |> LazyHTML.to_tree()
            |> Enum.map(fn {_, _, text} -> IO.iodata_to_binary(text) end)

          kind =
            cond do
              codes != [] -> :backup_codes
              String.starts_with?(name, "setup") or String.starts_with?(name, "verify") -> :verify
              true -> :show
            end

          render = %{
            kind: kind,
            secret: secret,
            uri: Dawarich.Auth.TwoFactor.Totp.provisioning_uri(secret, row["email"]),
            codes: codes,
            user: %{otp_required_for_login: row["after"]["enabled"]}
          }

          render =
            if row["status"] == 422,
              do: Map.put(render, :reason, :invalid_verification_code),
              else: render

          incoming = Map.put(session, "locale", row["locale"])

          response =
            Response.form(
              request(incoming, user, row["method"], row["path"]),
              user,
              render,
              row["status"],
              context
            )

          assert response.assigns.rails_session == incoming
          assert response.status == row["status"] and response.halted

          assert ParityHTML.fragment(response.resp_body, ".min-h-content.w-full.my-5") ==
                   ParityHTML.normalize(page),
                 name

          expected_title =
            DawarichWeb.Layouts.page_title(row["locale"], Form.title(kind, row["locale"]))

          assert response.resp_body
                 |> LazyHTML.from_document()
                 |> LazyHTML.query("title")
                 |> LazyHTML.text() == expected_title

          for {_, attrs, _} <-
                response.resp_body
                |> LazyHTML.from_document()
                |> LazyHTML.query("input[name=authenticity_token]")
                |> LazyHTML.to_tree() do
            assert DawarichWeb.RailsCsrf.valid?(incoming, Map.new(attrs)["value"])
          end

          assert response.assigns.rails_session == incoming
          assert Enum.into(response.assigns.flash_messages, %{}) == row["flash"]
          assert_response(response, row, incoming)
          refute response.resp_body =~ "response-synthetic-cookie-key"

          assert response.resp_body
                 |> LazyHTML.from_document()
                 |> LazyHTML.query(".min-h-content.w-full.my-5 [phx-submit]")
                 |> LazyHTML.to_tree() == []
        end

        reasons = [
          {"wrong_password", :incorrect_password},
          {"invalid_code", :provide_a_valid_two_factor_code_or_backup_code_to},
          {"disable_totp", :two_factor_authentication_disabled},
          {"unavailable", :two_factor_authentication_is_not_configured_on_this_instance}
        ]

        for {name, reason} <- reasons do
          row = Enum.find(@rows, &(&1["name"] == name))
          response = Response.redirect(request(session, user), reason, context)
          assert response.status == row["status"] and response.halted and response.resp_body == ""
          assert get_resp_header(response, "location") == [row["location"]]

          expected =
            Map.put(session, "flash", %{"discard" => [], "flashes" => row["cookie_flash"]})

          assert response.assigns.rails_session == expected
          assert_response(response, row, expected)
          show = %{kind: :show, user: %{otp_required_for_login: false}}
          next = Response.form(request(expected, user, "GET"), user, show, 200, context)
          assert Enum.into(next.assigns.flash_messages, %{}) == row["cookie_flash"]
          assert next.assigns.rails_session == session

          again =
            Response.form(
              request(next.assigns.rails_session, user, "GET"),
              user,
              show,
              200,
              context
            )

          assert again.assigns.flash_messages == []
          assert get_resp_header(next, "cache-control") == ["no-cache"]

          assert get_resp_header(again, "cache-control") == [
                   "max-age=0, private, must-revalidate"
                 ]
        end

        initial = Map.delete(session, "_csrf_token")

        first =
          Response.form(
            request(initial, user, "GET"),
            user,
            %{kind: :show, user: %{otp_required_for_login: false}},
            200,
            context
          )

        assert Map.drop(first.assigns.rails_session, ["_csrf_token"]) == initial

        [{_, csrf, _}] =
          first.resp_body
          |> LazyHTML.from_document()
          |> LazyHTML.query("meta[name=csrf-token]")
          |> LazyHTML.to_tree()

        assert DawarichWeb.RailsCsrf.valid?(first.assigns.rails_session, Map.new(csrf)["content"])
        huge = Map.put(session, "huge", String.duplicate("x", 6000))

        assert_raise DawarichWeb.RailsSession.Overflow, fn ->
          Response.redirect(request(huge, user), :incorrect_password, context)
        end

        assert_raise DawarichWeb.RailsSession.Overflow, fn ->
          Response.form(
            request(huge, user),
            user,
            %{kind: :show, user: %{otp_required_for_login: false}},
            422,
            context
          )
        end
      end)

    assert log == ""
  end

  defp request(session, user, method \\ "DELETE", path \\ "/settings/two_factor") do
    Plug.Test.conn(method, "http://www.example.com" <> path)
    |> Plug.Test.put_req_cookie("remember_user_token", "synthetic-remember-state")
    |> assign(:rails_session, session)
    |> assign(:current_user, user)
  end

  defp assert_response(response, row, session) do
    for {key, value} <- row["headers"], do: assert(get_resp_header(response, key) == [value], key)
    assert get_resp_header(response, "vary") == []
    assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-two-factor"]
    assert Map.keys(response.resp_cookies) == ["_dawarich_session"]
    assert response.cookies["remember_user_token"] == "synthetic-remember-state"
    cookie = response.resp_cookies["_dawarich_session"]

    assert cookie.http_only and cookie.same_site == "Lax" and cookie.path == "/" and
             not cookie.secure

    assert RailsCookies.decrypt(cookie.value, "_dawarich_session", @secret, DateTime.utc_now()) ==
             {:ok, session}
  end
end
