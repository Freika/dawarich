defmodule Dawarich.Mail.FamilyInvitationWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.I18n
  alias Dawarich.Mail.FamilyInvitationWorker

  @invitee "invitee@example.test"

  setup do
    for {name, value} <- [{"DOMAIN", "invite.example.test"}, {"RAILS_ENV", "production"}] do
      previous = System.get_env(name)
      System.put_env(name, value)

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    :ok
  end

  defp user!(email, settings, deleted_at \\ nil) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, deleted_at, created_at, updated_at) VALUES ($1, $2, $3, now(), now()) RETURNING id",
        [email, settings, deleted_at]
      )

    id
  end

  defp invitation!(inviter_id, status \\ 0) do
    [[family_id]] =
      rows(
        "INSERT INTO families (name, creator_id, created_at, updated_at) VALUES ('Home Crew', $1, now(), now()) RETURNING id",
        [inviter_id]
      )

    [[id]] =
      rows(
        """
        INSERT INTO family_invitations (email, token, status, family_id, invited_by_id, expires_at, created_at, updated_at)
        VALUES ($1, 'invite-token-1', $2, $3, $4, now() + interval '7 days', now(), now()) RETURNING id
        """,
        [@invitee, status, family_id, inviter_id]
      )

    id
  end

  defp args(invitation_id),
    do: %{"event_id" => Ecto.UUID.generate(), "invitation_id" => invitation_id, "locale" => "es"}

  defp subject(locale),
    do: I18n.t(locale, "mailers.family.invitation.subject", %{"family" => "Home Crew"})

  test "invitation: not pending sends nothing; locale is recipient, else inviter, else payload; accept URL uses DOMAIN" do
    inviter = user!("inviter@example.test", %{"locale" => "de"})

    accepted = invitation!(inviter, 1)
    assert perform_job(FamilyInvitationWorker, args(accepted)) == :ok
    refute_received {:mail, _}
    assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]

    rows("TRUNCATE families CASCADE")
    no_account = invitation!(inviter)
    assert perform_job(FamilyInvitationWorker, args(no_account)) == :ok
    assert_received {:mail, %{to: @invitee} = mail}
    assert {:ok, mail.subject} == subject("de")
    assert mail.text =~ "https://invite.example.test/family/invitations/invite-token-1"
    assert mail.html =~ ~s(href="https://invite.example.test/family/invitations/invite-token-1")
    assert mail.text =~ "inviter@example.test"

    rows("TRUNCATE families CASCADE")
    recipient = user!(@invitee, %{"locale" => "fr"})
    with_account = invitation!(inviter)
    assert perform_job(FamilyInvitationWorker, args(with_account)) == :ok
    assert_received {:mail, mail}
    assert {:ok, mail.subject} == subject("fr")

    rows("UPDATE users SET settings = '{}' WHERE id = ANY($1)", [[inviter, recipient]])
    rows("TRUNCATE families CASCADE")
    neither = invitation!(inviter)
    assert perform_job(FamilyInvitationWorker, args(neither)) == :ok
    assert_received {:mail, mail}
    assert {:ok, mail.subject} == subject("es")
  end

  test "sends under the invitation's claim once" do
    invitation_id = invitation!(user!("inviter@example.test", %{}))

    assert perform_job(FamilyInvitationWorker, args(invitation_id)) == :ok
    assert perform_job(FamilyInvitationWorker, args(invitation_id)) == :ok
    assert_received {:mail, _}
    refute_received {:mail, _}

    assert rows("SELECT provider_key, delivered_at IS NOT NULL FROM phoenix.delivery_claims") ==
             [["family-invitation:#{invitation_id}", true]]
  end

  test "invitation N of a recreated database (another token) gets another Message-ID at DOMAIN" do
    invitation_id = invitation!(user!("inviter@example.test", %{}))

    assert perform_job(FamilyInvitationWorker, args(invitation_id)) == :ok
    assert_received {:mail, %{message_id: first}}
    assert first =~ ~r/\A<[0-9a-f]{64}@invite\.example\.test>\z/

    rows("TRUNCATE phoenix.delivery_claims")
    rows("UPDATE family_invitations SET token = 'invite-token-2' WHERE id = $1", [invitation_id])

    assert perform_job(FamilyInvitationWorker, args(invitation_id)) == :ok
    assert_received {:mail, %{message_id: second}}
    refute first == second
  end

  test "a soft-deleted inviter cancels the job (ED-080); a missing invitation is a no-op" do
    inviter = user!("inviter@example.test", %{}, DateTime.utc_now())
    invitation_id = invitation!(inviter)

    assert perform_job(FamilyInvitationWorker, args(invitation_id)) ==
             {:cancel, "inviter missing"}

    assert perform_job(FamilyInvitationWorker, args(invitation_id + 1_000)) == :ok
    refute_received {:mail, _}
  end

  test "an unset DOMAIN fails the attempt and leaves the claim undelivered" do
    System.delete_env("DOMAIN")
    invitation_id = invitation!(user!("inviter@example.test", %{}))

    assert perform_job(FamilyInvitationWorker, args(invitation_id)) ==
             {:error, "DOMAIN is not set"}

    refute_received {:mail, _}
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
  end
end
