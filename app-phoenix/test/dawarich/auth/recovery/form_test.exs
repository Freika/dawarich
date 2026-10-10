defmodule Dawarich.Auth.Recovery.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.AuthMarkup
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

  test "renders every recovery form exactly as the Rails Devise views do, byte for byte" do
    assert Enum.sort(Map.keys(@markup)) == Enum.sort(Map.keys(@cases))

    for {name, row} <- @markup do
      {view, assigns} = @cases[name]
      assigns = if row["token"], do: Map.put(assigns, :token, row["token"]), else: assigns
      html = Form.render(view, "CSRF", assigns, "en", row["registration"])
      assert AuthMarkup.strict(html) == AuthMarkup.strict(row["html"]), name
    end
  end
end
