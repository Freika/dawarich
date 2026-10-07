defmodule Dawarich.A12f3bM01Test do
  use Dawarich.JobsCase

  alias Dawarich.Mail.{Smtp, SmtpConfig, WelcomeWorker}

  @tag a12f3b_case: "M01a"
  test "native mail transport preserves every source SMTP configuration" do
    for ssl <- ["true", "false"],
        starttls <- ["true", "false"],
        auth <- ["plain", "login", "cram_md5", "none"] do
      options =
        SmtpConfig.options(%{
          "SMTP_SERVER" => "smtp.example.test",
          "SMTP_PORT" => "587",
          "SMTP_SSL" => ssl,
          "SMTP_STARTTLS" => starttls,
          "SMTP_AUTHENTICATION" => auth,
          "SMTP_DOMAIN" => "mail.example.test"
        })

      assert options[:ssl] == (ssl == "true")
      assert options[:tls] == if(ssl == "false" and starttls == "true", do: :always, else: :never)
      assert options[:auth] == if(auth == "none", do: :never, else: :always)
      assert options[:hostname] == ~c"mail.example.test"
      assert options[:port] == 587
    end

    for format <- [:html_only, :multipart] do
      message = %{
        from: "Sender <sender@example.test>",
        to: "recipient@example.test",
        reply_to: "reply@example.test",
        subject: "Mail",
        html: "<p>Mail</p>",
        text: "Mail"
      }

      message = if format == :html_only, do: Map.put(message, :format, format), else: message
      {_, _, headers, _, _} = message |> Smtp.encode() |> :mimemail.decode(encoding: :none)
      assert {"Reply-To", "reply@example.test"} in headers
      assert SmtpConfig.envelope_from(message.from) == "sender@example.test"
    end
  end

  @tag a12f3b_case: "M01b"
  test "failed SMTP delivery leaves claim and sent marker retryable" do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('smtp@example.test','{}',now(),now()) RETURNING id"
      )

    args = %{"user_id" => id, "locale" => "fr", "event_id" => Ecto.UUID.generate()}
    Process.put(:transport_result, {:error, :rejected})
    assert WelcomeWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, first}
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
    Process.delete(:transport_result)
    assert WelcomeWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, second}
    assert first.message_id == second.message_id
    assert rows("SELECT delivered_at IS NOT NULL FROM phoenix.delivery_claims") == [[true]]
    assert WelcomeWorker.perform(%Oban.Job{args: args}) == :ok
    refute_received {:mail, _}
  end
end
