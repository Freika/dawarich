defmodule Dawarich.Mail.WelcomeWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Mail.{Delivery, WelcomeWorker}
  alias Dawarich.RailsSecret

  defp user!(attrs \\ %{}) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, deleted_at, created_at, updated_at) VALUES ($1, $2, $3, now(), now()) RETURNING id",
        [
          Map.get(attrs, :email, "welcome@example.test"),
          Map.get(attrs, :settings, %{"locale" => "de"}),
          Map.get(attrs, :deleted_at)
        ]
      )

    id
  end

  defp args(user_id, event_id \\ Ecto.UUID.generate()),
    do: %{"event_id" => event_id, "user_id" => user_id, "locale" => "fr"}

  test "sends once in the user's locale under the welcome claim with a deterministic Message-ID" do
    user_id = user!()
    event_id = Ecto.UUID.generate()
    key = "welcome:#{user_id}"
    [[created_at]] = rows("SELECT created_at FROM users WHERE id = $1", [user_id])

    message_id =
      Delivery.message_id(
        "mail.user.welcome",
        key,
        NaiveDateTime.to_iso8601(created_at),
        System.get_env(),
        RailsSecret.fetch()
      )

    assert perform_job(WelcomeWorker, args(user_id, event_id)) == :ok
    assert_received {:mail, %{to: "welcome@example.test", message_id: ^message_id} = mail}
    assert {:ok, mail.subject} == Dawarich.I18n.t("de", "mailers.users.welcome.subject")

    assert [[^key, delivered_at]] =
             rows("SELECT provider_key, delivered_at FROM phoenix.delivery_claims")

    assert %DateTime{} = delivered_at

    assert perform_job(WelcomeWorker, args(user_id)) == :ok
    refute_received {:mail, _}
  end

  test "user N of a recreated database (another created_at) gets another Message-ID" do
    user_id = user!()

    assert perform_job(WelcomeWorker, args(user_id)) == :ok
    assert_received {:mail, %{message_id: first}}

    rows("TRUNCATE phoenix.delivery_claims")

    rows("UPDATE users SET created_at = created_at + interval '1 microsecond' WHERE id = $1", [
      user_id
    ])

    assert perform_job(WelcomeWorker, args(user_id)) == :ok
    assert_received {:mail, %{message_id: second}}
    refute first == second
  end

  test "a missing or soft-deleted user is a silent no-op with no claim" do
    deleted = user!(%{email: "gone@example.test", deleted_at: DateTime.utc_now()})

    assert perform_job(WelcomeWorker, args(deleted)) == :ok
    assert perform_job(WelcomeWorker, args(deleted + 1_000)) == :ok
    refute_received {:mail, _}
    assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]
  end
end
