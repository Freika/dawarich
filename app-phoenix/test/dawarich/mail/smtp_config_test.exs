defmodule Dawarich.Mail.SmtpConfigTest do
  use ExUnit.Case, async: true
  alias Dawarich.Mail.SmtpConfig

  @base %{
    "SMTP_SERVER" => "smtp.example.test",
    "SMTP_PORT" => "587",
    "SMTP_USERNAME" => "u",
    "SMTP_PASSWORD" => "p"
  }

  test "defaults like Rails' SmtpConfig: STARTTLS, PLAIN-style auth, 60 s read timeout, EHLO localhost" do
    options = SmtpConfig.options(@base)
    assert options[:relay] == ~c"smtp.example.test"
    assert options[:port] == 587
    assert options[:ssl] == false
    assert options[:tls] == :always
    assert options[:auth] == :always
    assert options[:username] == ~c"u"
    assert options[:password] == ~c"p"
    assert options[:hostname] == ~c"localhost"
    assert options[:timeout] == 60_000
    assert options[:retries] == 0
    assert options[:tls_options][:verify] == :verify_peer
  end

  test "port 465 means implicit TLS unless SMTP_SSL says otherwise" do
    assert SmtpConfig.options(Map.put(@base, "SMTP_PORT", "465"))[:ssl] == true
    assert SmtpConfig.options(Map.put(@base, "SMTP_PORT", "465"))[:tls] == :never

    assert SmtpConfig.options(Map.merge(@base, %{"SMTP_PORT" => "465", "SMTP_SSL" => "false"}))[
             :ssl
           ] == false
  end

  test "none disables AUTH and drops the credentials; STARTTLS and verification can be turned off" do
    options =
      SmtpConfig.options(
        Map.merge(@base, %{
          "SMTP_AUTHENTICATION" => "none",
          "SMTP_STARTTLS" => "false",
          "SMTP_OPENSSL_VERIFY_MODE" => "none"
        })
      )

    assert options[:auth] == :never
    refute Keyword.has_key?(options, :username)
    assert options[:tls] == :never
    assert options[:tls_options] == [verify: :verify_none]
  end

  test "refuses mechanisms gen_smtp cannot speak instead of sending unauthenticated" do
    assert_raise ArgumentError, ~r/SMTP_AUTHENTICATION=ntlm/, fn ->
      SmtpConfig.options(Map.put(@base, "SMTP_AUTHENTICATION", "ntlm"))
    end
  end

  test "development's E2E sink port wins when no SMTP server is configured" do
    assert SmtpConfig.options(%{"E2E_SMTP_PORT" => "2525"}) == [
             relay: ~c"127.0.0.1",
             port: 2525,
             ssl: false,
             tls: :never,
             auth: :never,
             retries: 0,
             timeout: 60_000
           ]
  end

  test "uses an explicit gen_smtp connection timeout in every mode" do
    assert SmtpConfig.options(@base)[:timeout] == 60_000
    assert SmtpConfig.options(%{"E2E_SMTP_PORT" => "2525"})[:timeout] == 60_000
  end

  test "the envelope sender is the bare address" do
    assert SmtpConfig.envelope_from("Dawarich <hi@example.test>") == "hi@example.test"
    assert SmtpConfig.envelope_from(" hi@example.test ") == "hi@example.test"
  end
end
