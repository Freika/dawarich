defmodule Dawarich.Mail.ArchivalApproachingWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Mail.ArchivalApproachingWorker

  @epoch "2026-03-29T03:30:00+02:00"

  setup do
    for {name, value} <- [
          {"SELF_HOSTED", "false"},
          {"MANAGER_URL", "https://manager.example.test"},
          {"JWT_SECRET_KEY", "archival-secret"}
        ] do
      previous = System.get_env(name)
      System.put_env(name, value)

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    :ok
  end

  defp user!(attrs \\ %{}) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, deleted_at, created_at, updated_at) VALUES ($1, $2, $3, now(), now()) RETURNING id",
        [
          "lite@example.test",
          Map.get(attrs, :settings, %{"locale" => "de"}),
          Map.get(attrs, :deleted_at)
        ]
      )

    id
  end

  defp args(user_id, event_id \\ Ecto.UUID.generate()),
    do: %{"event_id" => event_id, "user_id" => user_id, "locale" => "en", "epoch" => @epoch}

  defp claims,
    do: rows("SELECT provider_key, delivered_at IS NOT NULL FROM phoenix.delivery_claims")

  test "sends the upgrade link in the user's locale under the epoch's claim" do
    user_id = user!()

    assert perform_job(ArchivalApproachingWorker, args(user_id)) == :ok
    assert_received {:mail, %{to: "lite@example.test"} = mail}

    assert {:ok, mail.subject} ==
             Dawarich.I18n.t("de", "mailers.users.archival_approaching.subject")

    assert mail.text =~ "https://manager.example.test/auth/dawarich?token="
    assert claims() == [["archival-approaching:#{user_id}:#{@epoch}", true]]
  end

  test "a missing JWT_SECRET_KEY fails the attempt, sends nothing and keeps the claim undelivered" do
    System.delete_env("JWT_SECRET_KEY")
    user_id = user!()

    assert perform_job(ArchivalApproachingWorker, args(user_id)) ==
             {:error, "JWT_SECRET_KEY is not set"}

    refute_received {:mail, _}
    assert claims() == [["archival-approaching:#{user_id}:#{@epoch}", false]]
  end

  test "a missing or soft-deleted user is a silent no-op with no claim" do
    deleted = user!(%{deleted_at: DateTime.utc_now()})

    assert perform_job(ArchivalApproachingWorker, args(deleted)) == :ok
    assert perform_job(ArchivalApproachingWorker, args(deleted + 1_000)) == :ok
    refute_received {:mail, _}
    assert claims() == []
  end
end
