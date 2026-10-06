defmodule Dawarich.A12f3bM08Test do
  use Dawarich.JobsCase
  alias Dawarich.Mail.{TestEmail, TestEmailWorker}

  @tag a12f3b_case: "M08a"
  test "test email preserves source header mail format and sync mode" do
    start_oban(:mail_test_email)

    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('test@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    user = %{id: id, email: "test@example.test", settings: %{"locale" => "de"}}

    for env <- [
          %{
            "SMTP_SERVER" => "smtp.example.test",
            "SMTP_AUTHENTICATION" => "plain",
            "SMTP_STARTTLS" => "true"
          },
          %{"SMTP_SERVER" => "smtp.example.test", "SMTP_PORT" => "465", "SMTP_SSL" => "true"}
        ] do
      assert TestEmail.supported?(env)
      assert {:notice, _} = TestEmail.run(user, "fr", env, oban: :mail_test_email)
      refute_received {:mail, _}
    end

    [[args]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id LIMIT 1")
    assert TestEmailWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, mail}
    assert mail.to == "test@example.test"
    assert mail.locale == "de"
    assert mail.format == :html_only
    refute Map.has_key?(mail, :text)
    assert {:ok, mail.subject} == Dawarich.I18n.t("de", "mailers.users.test_email.subject")
  end

  @tag a12f3b_case: "M08b"
  test "test email worker reports failure without delivered marker" do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('failure@example.test','{}',now(),now()) RETURNING id"
      )

    args = %{"user_id" => id, "locale" => "fr"}
    Process.put(:transport_result, {:error, :rejected})
    assert TestEmailWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, _}

    assert rows("SELECT count(*) FROM phoenix.delivery_claims WHERE delivered_at IS NOT NULL") ==
             [[0]]

    Process.delete(:transport_result)
    assert TestEmailWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, _}
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [id])
    assert TestEmailWorker.perform(%Oban.Job{args: args}) == :ok
    refute_received {:mail, _}
  end
end
