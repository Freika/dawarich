defmodule Dawarich.Mail.Sync1153TestEmailTest do
  use Dawarich.JobsCase
  alias Dawarich.Mail.TestEmail

  test "test email queues through the mail worker without attempting SMTP inline" do
    start_oban(__MODULE__.Oban)

    rows(
      "INSERT INTO users(id,email,settings,admin,created_at,updated_at) VALUES(115301,'synthetic@example.invalid','{}',true,now(),now())"
    )

    user = %{id: 115_301, admin: true, email: "synthetic@example.invalid", settings: %{}}
    env = %{"SMTP_SERVER" => "synthetic.example.invalid"}
    assert {:notice, message} = TestEmail.run(user, "en", env, oban: __MODULE__.Oban)
    assert message =~ "queued"

    assert [[%{"user_id" => 115_301, "locale" => "en", "event_id" => event_id}]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Mail.TestEmailWorker'")

    refute_received {:mail, _}

    assert :ok =
             Dawarich.Mail.TestEmailWorker.perform(%Oban.Job{
               args: %{"user_id" => user.id, "locale" => "en", "event_id" => event_id}
             })

    assert_received {:mail, %{to: "synthetic@example.invalid", format: :html_only}}
  end
end
