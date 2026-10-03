defmodule Dawarich.Auth.Recovery.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.AuthRecovery.Form

  @markup Path.expand("../../../fixtures/auth/recovery/http.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("markup")
  @cases %{
    "password_new" => {:password_new, %{}},
    "password_edit" => {:password_edit, %{token: "synthetic"}},
    "unlock_new" => {:unlock_new, %{}},
    "unlock_invalid" => {:unlock_new, %{error: :invalid}},
    "password_edit_errors" =>
      {:password_edit, %{error: {:validation, [:confirmation, :too_short]}}},
    "password_edit_invalid" => {:password_edit, %{error: :invalid}},
    "password_edit_blank_token" => {:password_edit, %{error: :blank_token}},
    "password_edit_expired" => {:password_edit, %{error: :expired}}
  }

  test "renders every recovery form as the Rails Devise views do" do
    assert Enum.sort(Map.keys(@markup)) == Enum.sort(Map.keys(@cases))

    for {name, row} <- @markup do
      {view, assigns} = @cases[name]
      assigns = if row["token"], do: Map.put(assigns, :token, row["token"]), else: assigns
      html = Form.render(view, "masked", assigns, "en", row["registration"])
      assert ParityHTML.normalize(html) == ParityHTML.normalize(row["html"]), name
    end
  end
end
