defmodule DawarichWeb.AuthPagesParityTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.ParityHTML

  for locale <- ~w(en de es fr pl ca zh),
      page <- ~w(sign_in sign_up password_new password_edit unlock_new) do
    @locale locale
    @page page
    test "#{@page} in #{@locale} matches Rails 1.16.0" do
      html =
        case @page do
          "sign_in" ->
            DawarichWeb.AuthForm.render("CSRF", "", locale: @locale, registration_enabled: true)

          "sign_up" ->
            DawarichWeb.AuthRegistration.Form.render("CSRF", "", [], nil, @locale)
            |> IO.iodata_to_binary()

          page ->
            DawarichWeb.AuthRecovery.Form.render(
              String.to_existing_atom(page),
              "CSRF",
              %{token: "synthetic-reset"},
              @locale,
              true
            )
        end

      html = String.replace(html, "data-auth-form", "data-native-auth-form")
      html = String.replace(html, ~s(for="user_remember_me" ), "")

      html =
        String.replace(
          html,
          ~s(class="text-center lg:text-left min-w-0 [overflow-wrap:anywhere]"),
          ~s(class="text-center lg:text-left")
        )

      phoenix = ParityHTML.normalize(html)

      rails =
        File.read!("test/fixtures/auth/pages/#{@page}_#{@locale}.html") |> ParityHTML.normalize()

      assert phoenix == rails, ParityHTML.first_difference(phoenix, rails)
    end
  end

  for locale <- ~w(en de es fr pl ca zh),
      page <-
        ~w(registration_disabled invitation_sign_in invitation_sign_up cloud_sign_up providers_only providers_with_credentials) do
    @locale locale
    @page page
    test "#{@page} in #{@locale} matches Rails 1.16.0" do
      invitation = %{
        name: "Auth fixture family",
        inviter: "auth-inviter@example.invalid",
        email: "auth-invitee@example.invalid",
        token: "synthetic-auth-invitation"
      }

      html =
        case @page do
          "registration_disabled" ->
            DawarichWeb.AuthForm.render("CSRF", "", locale: @locale, registration_enabled: false)

          "invitation_sign_in" ->
            DawarichWeb.AuthForm.render("CSRF", "", locale: @locale, invitation: invitation)

          "invitation_sign_up" ->
            DawarichWeb.AuthRegistration.Form.render(
              "CSRF",
              invitation.email,
              [],
              invitation,
              @locale
            )
            |> IO.iodata_to_binary()

          "cloud_sign_up" ->
            DawarichWeb.AuthRegistration.Form.render("CSRF", "", [], nil, @locale,
              self_hosted: false,
              sitekey: "synthetic-sitekey"
            )
            |> IO.iodata_to_binary()

          page when page in ["providers_only", "providers_with_credentials"] ->
            DawarichWeb.AuthForm.render("CSRF", "",
              locale: @locale,
              email_password: @page != "providers_only",
              registration_enabled: true,
              providers: [
                %{
                  action: "/users/auth/openid_connect",
                  method: "POST",
                  csrf: "CSRF",
                  label:
                    DawarichWeb.Translate.t(@locale, "oauth_providers.sign_in_with_provider", %{
                      "provider" => "Openid Connect"
                    })
                }
              ]
            )
        end

      html =
        html
        |> String.replace("data-auth-form", "data-native-auth-form")
        |> String.replace(~s(for="user_remember_me" ), "")

      actual = ParityHTML.normalize(html)

      expected =
        File.read!("test/fixtures/auth/pages/#{@page}_#{@locale}.html") |> ParityHTML.normalize()

      assert actual == expected, ParityHTML.first_difference(actual, expected)
    end
  end

  for locale <- ~w(en de es fr pl ca zh),
      page <- ~w(sign_up_errors password_edit_errors unlock_errors) do
    @locale locale
    @page page
    test "#{@page} in #{@locale} matches Rails 1.16.0" do
      html =
        case @page do
          "sign_up_errors" ->
            params = %{
              "email" => "bad",
              "password" => "short",
              "password_confirmation" => "different"
            }

            errors =
              Dawarich.Auth.AccountValidation.validate(params, "",
                email_taken: false,
                current_password_valid: true,
                locale: @locale
              ).errors

            messages = Dawarich.Auth.AccountValidation.messages(errors, @locale)

            DawarichWeb.AuthRegistration.Form.render("CSRF", "bad", messages, nil, @locale,
              invalid: Enum.map(errors, fn {key, _, _} -> to_string(key) end)
            )
            |> IO.iodata_to_binary()

          page ->
            DawarichWeb.AuthRecovery.Form.render(
              if(page == "unlock_errors", do: :unlock_new, else: :password_edit),
              "CSRF",
              %{token: "synthetic-invalid", error: :invalid},
              @locale,
              true
            )
        end

      actual =
        html
        |> String.replace("data-auth-form", "data-native-auth-form")
        |> String.replace("data-auth-error-summary", "data-native-auth-error-summary")
        |> String.replace(~s( role="alert"), "")
        |> String.replace(~s( tabindex="-1"), "")
        |> String.replace(" min-w-0 [overflow-wrap:anywhere]", "")
        |> String.replace(~s( aria-invalid="true"), "")
        |> String.replace(~s( aria-describedby="error_explanation"), "")
        |> String.replace(
          ~s(aria-describedby="password-hint error_explanation"),
          ~s(aria-describedby="password-hint")
        )
        |> ParityHTML.normalize()

      expected =
        File.read!("test/fixtures/auth/pages/#{@page}_#{@locale}.html") |> ParityHTML.normalize()

      assert actual == expected, ParityHTML.first_difference(actual, expected)
    end
  end

  test "confirmation routes remain unavailable as on the non-confirmable Rails User" do
    routes = File.read!("test/fixtures/auth/pages/confirmation_routes.json") |> Jason.decode!()
    assert length(routes) == 3

    for route <- routes do
      assert route["status"] == 404

      assert Phoenix.Router.route_info(
               DawarichWeb.Router,
               route["method"],
               route["path"],
               "www.example.com"
             ) == :error
    end
  end
end
