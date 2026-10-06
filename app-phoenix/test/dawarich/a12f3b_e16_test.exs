defmodule Dawarich.A12f3bE16Test do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Jobs.{Drain, Ownership}
  alias Dawarich.Mail.{UserCallbacks, WelcomeWorker}
  alias Dawarich.UserData.ImportCommands

  @tag a12f3b_case: "E16a"
  test "E16 native owner accepts every retained argument and continuation shape" do
    [[user]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('callback@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    at = DateTime.add(DateTime.utc_now(), 3600)
    digest = String.duplicate("a", 64)

    link = %{
      "link_url" => "https://example.test/confirm?token=synthetic",
      "link_token_sha256" => digest,
      "link_expires_at" => DateTime.to_unix(at)
    }

    for {type, options} <- [
          {"welcome", %{}},
          {"explore_features", %{}},
          {"archival_approaching", %{"epoch" => "2026-09-01T03:00:00+02:00"}},
          {"oauth_account_link", Map.put(link, "provider_label", "Google")},
          {"account_destroy_confirmation", link}
        ] do
      key =
        if type == "explore_features",
          do: "users.explore_features_mail",
          else: "mail.user." <> type

      Ownership.put!(ScratchRepo, "command:" <> key, :oban)
      payload = Map.merge(%{"user_id" => user, "locale" => "fr"}, options)
      event = Ecto.UUID.generate()

      assert UserCallbacks.enqueue(ScratchRepo, type, payload, event_id: event, scheduled_at: at) ==
               :ok

      assert UserCallbacks.enqueue(ScratchRepo, type, payload, event_id: event, scheduled_at: at) ==
               :ok

      assert [[^key, ^payload, ^at]] =
               rows(
                 "SELECT command_type,payload,scheduled_at FROM job_outbox WHERE event_id=$1",
                 [Ecto.UUID.dump!(event)]
               )
    end

    assert [[5]] = rows("SELECT count(*) FROM job_outbox")
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert "pending_outbox" in Drain.status(ScratchRepo).binary_reasons
    assert UserCallbacks.enqueue(ScratchRepo, "welcome", %{}) == {:error, "invalid_payload"}
    assert UserCallbacks.enqueue(ScratchRepo, "unknown", %{}) == {:error, :unknown_email_type}

    for type <-
          ~w(trial_expired trial_expires_soon post_trial_reminder_early post_trial_reminder_late) do
      assert UserCallbacks.enqueue(ScratchRepo, type, %{"user_id" => user}) == :retired
    end

    Ownership.put!(ScratchRepo, "command:users.import_data", :oban)

    assert ImportCommands.enqueue(ScratchRepo, %{id: 123, user_id: user}, %{
             zone: "Europe/Berlin",
             locale: "de"
           }) == :ok

    assert [
             [
               %{
                 "import_id" => 123,
                 "user_id" => ^user,
                 "time_zone" => "Europe/Berlin",
                 "locale" => "de"
               }
             ]
           ] = rows("SELECT payload FROM job_outbox WHERE command_type='users.import_data'")

    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")

    assert perform_job(WelcomeWorker, %{
             "user_id" => user,
             "locale" => "fr",
             "event_id" => Ecto.UUID.generate()
           }) == :ok

    assert_received {:mail, %{to: "callback@example.test", subject: subject}}
    assert {:ok, ^subject} = Dawarich.I18n.t("de", "mailers.users.welcome.subject")
  end
end
