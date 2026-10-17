defmodule Dawarich.Auth.Recovery.MessagesTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Recovery.Messages

  @rows Jason.decode!(
          File.read!(Path.expand("../../../fixtures/auth/recovery/errors.json", __DIR__))
        )
  test "matches the Rails EN/DE/FR headings and full error messages" do
    kinds = %{
      "invalid" => :invalid,
      "blank_token" => :blank_token,
      "expired" => :expired,
      "too_short" => {:validation, [:too_short]},
      "too_long" => {:validation, [:too_long]},
      "confirmation" => {:validation, [:confirmation]},
      "blank" => {:validation, [:blank]},
      "short_mismatch" => {:validation, [:confirmation, :too_short]}
    }

    assert length(@rows) == 27

    for row <- @rows do
      view = if row["view"] == "unlock_new", do: :unlock_new, else: :password_edit

      result = Messages.error(view, kinds[row["kind"]], row["locale"])
      assert result.messages == row["messages"]
      assert result.heading == row["heading"]
    end
  end
end
