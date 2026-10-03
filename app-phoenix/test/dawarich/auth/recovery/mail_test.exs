defmodule Dawarich.Auth.Recovery.MailTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Recovery.Mail

  @rows Jason.decode!(
          File.read!(Path.expand("../../../fixtures/auth/recovery/mail.json", __DIR__))
        )
  test "matches all six actual Rails HTML bodies, subjects and recipient headers" do
    kinds = %{
      "reset_password_instructions" => :reset_password_instructions,
      "unlock_instructions" => :unlock_instructions
    }

    for row <- @rows do
      assert {:ok, message} =
               Mail.build(
                 kinds[row["kind"]],
                 row["email"],
                 row["locale"],
                 row["raw"],
                 "http://www.example.com",
                 %{"SMTP_FROM" => "auth-oracle@dawarich.test"}
               )

      assert message.format == :html_only
      refute Map.has_key?(message, :text)
      assert message.html == row["html"]
      assert message.subject == row["subject"]
      assert [message.from] == row["from"]
      assert [message.to] == row["to"]
      assert [message.reply_to] == row["wire_reply_to"]
      assert row["wire_sender"] == nil
    end
  end

  test "requires explicit valid absolute owner URL and rejects foreign surfaces" do
    assert {:error, :base_url} =
             Mail.build(:unlock_instructions, "x@test", "en", "safe", nil, %{})

    assert {:error, :base_url} =
             Mail.build(:unlock_instructions, "x@test", "en", "safe", "javascript:alert(1)", %{})

    assert {:error, :surface} =
             Mail.build(
               :confirmation_instructions,
               "x@test",
               "en",
               "safe",
               "http://www.example.com",
               %{}
             )
  end
end
