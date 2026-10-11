defmodule Dawarich.Auth.Recovery.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.{AuthMarkup, NativeAuthHTTP}
  alias DawarichWeb.AuthRecovery.Form

  @markup AuthMarkup.fixture()["recovery"]
  @cases %{
    "password_new" => {:password_new, %{}},
    "password_new_registration" => {:password_new, %{}},
    "unlock_new_registration" => {:unlock_new, %{}},
    "password_edit" => {:password_edit, %{token: "synthetic"}},
    "unlock_new" => {:unlock_new, %{}},
    "unlock_invalid" => {:unlock_new, %{error: :invalid}},
    "password_edit_errors" =>
      {:password_edit, %{error: {:validation, [:confirmation, :too_short]}}},
    "password_edit_invalid" => {:password_edit, %{error: :invalid}},
    "password_edit_blank_token" => {:password_edit, %{error: :blank_token}},
    "password_edit_expired" => {:password_edit, %{error: :expired}}
  }

  test "native recovery forms submit only source fields and retain reset capability" do
    html = Form.render(:password_edit, "CSRF", %{token: "synthetic-reset-token"}, "en", false)
    dom = LazyHTML.from_fragment(html)

    assert Enum.count(
             LazyHTML.query(dom, "form[data-auth-form][method=post][action='/users/password']")
           ) == 1

    assert LazyHTML.attribute(LazyHTML.query(dom, "input[name=_method]"), "value") == ["put"]

    capability_present =
      LazyHTML.attribute(LazyHTML.query(dom, "input[name='user[reset_password_token]']"), "value") ==
        ["synthetic-reset-token"]

    assert capability_present
    assert Enum.count(LazyHTML.query(dom, "input[name='user[password_confirmation]']")) == 1
  end

  test "recovery errors keep translated messages and empty credential values" do
    for locale <- ~w(en de es fr pl ca zh) do
      error = {:validation, [:confirmation, :too_short]}

      html =
        Form.render(
          :password_edit,
          "CSRF",
          %{
            token: "synthetic-reset-token",
            error: error,
            password: "synthetic-rejected-password"
          },
          locale,
          false
        )

      assert Enum.count(LazyHTML.query(LazyHTML.from_fragment(html), "form[data-auth-form]")) == 1

      for message <- Dawarich.Auth.Recovery.Messages.error(:password_edit, error, locale).messages,
          do: assert(String.contains?(NativeAuthHTTP.text(html, "#error_explanation"), message))

      refute html =~ "synthetic-rejected-password"

      for node <- LazyHTML.query(LazyHTML.from_fragment(html), "input[type=password]"),
          do: assert(LazyHTML.attribute(node, "value") in [[], [""]])
    end
  end

  test "recovery field errors have unique accessible labels and summary focus" do
    html =
      Form.render(
        :password_edit,
        "CSRF",
        %{error: {:validation, [:confirmation, :too_short]}},
        "de",
        false
      )

    dom = LazyHTML.from_fragment(html)

    assert Enum.count(
             LazyHTML.query(dom, "#error_explanation[data-auth-error-summary][tabindex='-1']")
           ) == 1

    for node <- LazyHTML.query(dom, "input[type=password]") do
      [id] = LazyHTML.attribute(node, "id")
      assert Enum.count(LazyHTML.query(dom, "label[for='#{id}']")) == 1

      assert Enum.any?(
               LazyHTML.attribute(node, "aria-describedby"),
               &String.contains?(&1, "error_explanation")
             )

      assert LazyHTML.attribute(node, "aria-invalid") == ["true"]
    end
  end

  test "recovery forms preserve every source field navigation and translated error case" do
    assert Enum.sort(Map.keys(@markup)) == Enum.sort(Map.keys(@cases))

    for {name, row} <- @markup do
      {view, assigns} = @cases[name]
      assigns = if row["token"], do: Map.put(assigns, :token, row["token"]), else: assigns
      html = Form.render(view, "CSRF", assigns, "en", row["registration"])
      same_fields = NativeAuthHTTP.fields(html) == NativeAuthHTTP.fields(row["html"])
      assert same_fields, name

      for selector <- ["h1", "label", "a", "#error_explanation h3", "#error_explanation li"],
          do:
            assert(
              NativeAuthHTTP.text(html, selector) == NativeAuthHTTP.text(row["html"], selector),
              name
            )
    end
  end
end
