defmodule Dawarich.A12f3bM02Test do
  use Dawarich.JobsCase
  alias Dawarich.Auth.Recovery.{MailWorker, Notification, Token}

  setup do
    names = ~w(DOMAIN SMTP_FROM RAILS_ENV)
    previous = Map.take(System.get_env(), names)

    System.put_env(%{
      "DOMAIN" => "mail.example.test",
      "SMTP_FROM" => "sender@example.test",
      "RAILS_ENV" => "production"
    })

    on_exit(fn ->
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
    end)

    start_oban(:mail_recovery_cases)
    :ok
  end

  defp queued!(kind, column) do
    raw = "synthetic-recovery-token"
    digest = Token.digest(column, raw, Dawarich.RailsSecret.fetch())

    [[id]] =
      rows(
        "INSERT INTO users(email,settings,#{column},created_at,updated_at) VALUES($1,$2,$3,now(),now()) RETURNING id",
        ["#{column}@example.test", %{"locale" => "de"}, digest]
      )

    notification = %Notification{kind: kind, user_id: id, raw: raw, digest: digest, locale: "en"}
    assert MailWorker.enqueue(notification, :mail_recovery_cases) == :ok
    [[args]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    {id, args, raw}
  end

  @tag a12f3b_case: "M02a"
  test "Devise reset and unlock deliver native source MIME and raw token" do
    for {kind, column} <- [
          reset_password_instructions: :reset_password_token,
          unlock_instructions: :unlock_token
        ] do
      {id, args, raw} = queued!(kind, column)
      rows("UPDATE users SET settings=$2 WHERE id=$1", [id, %{"locale" => " FR "}])
      assert MailWorker.perform(%Oban.Job{args: args}) == :ok
      assert_received {:mail, mail}
      assert mail.html =~ "#{column}=#{raw}"
      refute mail.html =~ args["digest"]
      assert mail.format == :html_only
      assert mail.reply_to == "sender@example.test"
      assert {:ok, mail.subject} == Dawarich.I18n.t("fr", "devise.mailer.#{kind}.subject")
    end
  end

  @tag a12f3b_case: "M02b"
  test "Devise mail failure preserves retry and recovery state ordering" do
    for {kind, column} <- [
          reset_password_instructions: :reset_password_token,
          unlock_instructions: :unlock_token
        ] do
      {id, args, _} = queued!(kind, column)
      Process.put(:transport_result, {:error, :rejected})
      assert MailWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
      assert_received {:mail, first}
      assert rows("SELECT #{column} FROM users WHERE id=$1", [id]) == [[args["digest"]]]

      assert rows("SELECT delivered_at FROM phoenix.delivery_claims WHERE event_id=$1", [
               Ecto.UUID.dump!(args["event_id"])
             ]) == [[nil]]

      Process.delete(:transport_result)
      assert MailWorker.perform(%Oban.Job{args: args}) == :ok
      assert_received {:mail, second}
      assert first.message_id == second.message_id
      rows("UPDATE users SET deleted_at=now() WHERE id=$1", [id])
      assert MailWorker.perform(%Oban.Job{args: args}) == :ok
      refute_received {:mail, _}
    end
  end
end
