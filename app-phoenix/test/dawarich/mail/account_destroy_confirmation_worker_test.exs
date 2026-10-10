defmodule Dawarich.Mail.AccountDestroyConfirmationWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  import ExUnit.CaptureLog

  alias Dawarich.Mail.AccountDestroyConfirmationWorker

  @token "header.claims.signature"
  @link_url "https://dawarich.example.test/auth/account_links/confirm?token=" <> @token
  @email "destroy@example.test"

  defp user!(attrs \\ %{}) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, deleted_at, created_at, updated_at) VALUES ($1, $2, $3, now(), now()) RETURNING id",
        [@email, %{"locale" => "fr"}, Map.get(attrs, :deleted_at)]
      )

    id
  end

  defp payload(user_id, overrides) do
    Map.merge(
      %{
        "user_id" => user_id,
        "locale" => "en",
        "link_url" => @link_url,
        "link_token_sha256" => Base.encode16(:crypto.hash(:sha256, @token), case: :lower),
        "link_expires_at" => System.os_time(:second) + 900
      },
      overrides
    )
  end

  defp command!(user_id, overrides \\ %{}) do
    payload = payload(user_id, overrides)

    event_id =
      outbox!(
        command_type: "mail.user.account_destroy_confirmation",
        payload: payload,
        aggregate_id: user_id
      )

    {:ok, args} = AccountDestroyConfirmationWorker.args_from_command(1, payload)
    {event_id, Map.put(args, "event_id", event_id)}
  end

  defp claims, do: rows("SELECT provider_key FROM phoenix.delivery_claims")

  test "sends the link read from the outbox under the digest's claim" do
    user_id = user!()
    {_event_id, args} = command!(user_id)

    assert perform_job(AccountDestroyConfirmationWorker, args) == :ok
    assert_received {:mail, %{to: @email} = mail}

    assert {:ok, mail.subject} ==
             Dawarich.I18n.t("fr", "mailers.users.account_destroy_confirmation.subject")

    assert mail.text =~ @link_url
    assert mail.html =~ ~s(href="#{@link_url}")
    assert claims() == [["destroy-confirmation:#{user_id}:#{args["link_token_sha256"]}"]]
  end

  test "destroy: an expired link, a pruned outbox row or a digest mismatch sends nothing" do
    user_id = user!()

    {_event_id, expired} = command!(user_id, %{"link_expires_at" => System.os_time(:second)})
    assert perform_job(AccountDestroyConfirmationWorker, expired) == :ok

    {event_id, pruned} = command!(user_id)
    rows("DELETE FROM job_outbox WHERE event_id = $1", [Ecto.UUID.dump!(event_id)])
    assert perform_job(AccountDestroyConfirmationWorker, pruned) == :ok

    {_event_id, mismatch} = command!(user_id, %{"link_token_sha256" => String.duplicate("0", 64)})

    assert perform_job(AccountDestroyConfirmationWorker, mismatch) ==
             {:cancel, "link digest mismatch"}

    refute_received {:mail, _}
    assert claims() == []
  end

  test "job logs contain neither the link URL nor the recipient email" do
    previous = Logger.level()
    Logger.configure(level: :info)
    :ok = Oban.Telemetry.attach_default_logger(level: :info)

    on_exit(fn ->
      Oban.Telemetry.detach_default_logger()
      Logger.configure(level: previous)
    end)

    {event_id, args} = command!(user!())

    log =
      capture_log([level: :info], fn ->
        assert perform_job(AccountDestroyConfirmationWorker, args) == :ok
      end)

    assert_received {:mail, %{to: @email}}
    assert log =~ event_id
    refute log =~ "dawarich.example.test"
    refute log =~ @token
    refute log =~ @email
  end

  test "a missing or soft-deleted user is a silent no-op with no claim" do
    deleted = user!(%{deleted_at: DateTime.utc_now()})
    {_event_id, args} = command!(deleted)
    {_event_id, missing} = command!(deleted + 1_000)

    assert perform_job(AccountDestroyConfirmationWorker, args) == :ok
    assert perform_job(AccountDestroyConfirmationWorker, missing) == :ok
    refute_received {:mail, _}
    assert claims() == []
  end
end
