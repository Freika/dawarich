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
      phoenix = ParityHTML.normalize(html)

      rails =
        File.read!("test/fixtures/auth/pages/#{@page}_#{@locale}.html") |> ParityHTML.normalize()

      assert phoenix == rails, ParityHTML.first_difference(phoenix, rails)
    end
  end
end
