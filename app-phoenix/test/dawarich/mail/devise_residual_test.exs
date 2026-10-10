defmodule Dawarich.Mail.DeviseResidualTest do
  use Dawarich.JobsCase

  alias Dawarich.Auth.Recovery.{Lifecycle, Mail}
  alias Dawarich.Jobs.Registry
  alias Dawarich.Mail.{DeviseResidual, ExploreFeatures, Residual, SmtpConfig}
  alias Dawarich.Test.MailWire

  @dir Path.expand("../../fixtures/mail/residual", __DIR__)

  test "reachable Devise contents match Rails recipient and body addresses" do
    fixture = read("content")

    rows =
      Enum.filter(
        fixture["cases"],
        &(&1["kind"] in ~w(reset_password_instructions unlock_instructions email_changed_current password_change))
      )

    expected =
      Enum.flat_map(
        ~w(reset_password_instructions unlock_instructions email_changed_current password_change),
        fn kind ->
          ids = for locale <- ~w(en de fallback_fr es fr pl ca zh), do: kind <> "_" <> locale
          ids
        end
      )

    assert Enum.map(rows, & &1["id"]) == expected

    kinds = %{
      "reset_password_instructions" => :reset_password_instructions,
      "unlock_instructions" => :unlock_instructions,
      "email_changed_current" => :email_changed,
      "password_change" => :password_change
    }

    for row <- rows do
      locale = ExploreFeatures.locale(row["settings"], row["ambient_locale"])
      kind = kinds[row["kind"]]
      env = %{"SMTP_FROM" => row["from_header"]}
      recipient = hd(row["to"])

      message =
        if kind in [:reset_password_instructions, :unlock_instructions] do
          case Mail.build(kind, recipient, locale, row["token"], row["base_url"], env) do
            {:ok, message} -> message
            _ -> flunk("recovery render failed: #{row["id"]}")
          end
        else
          DeviseResidual.message(kind, recipient, row["email"], locale, env)
        end

      same(message.html, row["tree"]["body"], "HTML", row)
      same(message.subject, row["subject"], "subject", row)
      same(message.to, recipient, "recipient", row)
      same(message.from, row["from_header"], "sender", row)
      same(SmtpConfig.envelope_from(message.reply_to), hd(row["reply_to"]), "reply-to", row)
      same(message.format, :html_only, "format", row)
      refute Map.has_key?(message, :text)
      wire = MailWire.phoenix(message)
      same(wire.type, {"text", "html"}, "MIME tree", row)
      same(wire.charset, "utf-8", "charset", row)
      same(String.replace(wire.body, "\r\n", "\n"), row["tree"]["body"], "wire HTML", row)
      same(wire.subject, row["subject"], "wire subject", row)
    end

    assert fixture["confirmation"]["module"] == false
    assert fixture["confirmation"]["fields"] == []
    assert fixture["confirmation"]["controllers"] == []
    assert fixture["confirmation"]["producer"] == false
    assert fixture["confirmation"]["dormant_template"] == true

    assert Mail.build(
             :confirmation_instructions,
             "x@test",
             "en",
             "synthetic",
             "http://www.example.com",
             %{}
           ) ==
             {:error, :surface}
  end

  test "retained and dormant auth triggers enqueue no native mail" do
    fixture = read("auth_intents")

    assert fixture["ownership"] == %{
             "reset_password_instructions" => "native_supported_recovery",
             "unlock_instructions" => "native_supported_recovery",
             "otp_account_locked" => "rails",
             "email_changed" => "rails_cloud",
             "password_change" => "rails_cloud",
             "confirmation" => "absent"
           }

    for dependency <- fixture["dependencies"] do
      root = Path.expand("..", File.cwd!())
      assert File.regular?(Path.join(root, dependency["oracle"]))
      assert File.regular?(Path.join(root, dependency["fixture"]))
    end

    for kind <-
          ~w(otp_account_locked email_changed password_change confirmation_instructions reconfirmation) do
      assert Registry.command("mail.auth." <> kind) == :error
    end

    start_oban(ResidualAuthOban)

    for context <- [%{self_hosted: false, oban: ResidualAuthOban}, %{oban: ResidualAuthOban}] do
      result = Lifecycle.reset("a12c-retained-synthetic", "synthetic-password", nil, context)
      assert result == {:handoff, :password_change_notification}
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    end

    Residual.message(:otp_account_locked, %{email: "x@test", settings: %{}}, "en", %{},
      base_url: "http://www.example.com"
    )

    for kind <- [:email_changed, :password_change] do
      DeviseResidual.message(kind, "old@test", "new@test", "en", %{})
    end

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert fixture["confirmation"]["producer"] == false
  end

  defp read(name), do: @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()

  defp same(actual, expected, field, row) do
    if actual != expected, do: flunk("#{field} differs: #{row["id"]}")
  end
end
