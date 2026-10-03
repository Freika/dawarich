defmodule Dawarich.Auth.SignInFormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.AuthMarkup
  alias DawarichWeb.AuthForm

  @markup AuthMarkup.fixture()["signin"]

  test "renders the sign-in page exactly as Rails' devise/sessions/new does, in every shape Phoenix serves" do
    assert Enum.sort(Map.keys(@markup)) ==
             ~w(signin signin_de signin_failed signin_fr signin_registration)

    for {name, row} <- @markup do
      html =
        AuthForm.render("CSRF", row["email"] || "",
          locale: row["locale"],
          registration_enabled: row["registration"]
        )

      assert AuthMarkup.strict(html) == AuthMarkup.strict(row["html"]), name
    end
  end

  test "escapes the submitted email" do
    html = AuthForm.render("token", "\"><script>alert(1)</script>")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end
end
