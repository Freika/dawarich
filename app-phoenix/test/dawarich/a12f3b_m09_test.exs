defmodule Dawarich.A12f3bM09Test do
  use Dawarich.JobsCase
  alias Dawarich.Mail.{FamilyInvitationWorker, FamilyLapseWorker}

  setup do
    names = ~w(DOMAIN RAILS_ENV SELF_HOSTED MANAGER_URL)
    previous = Map.take(System.get_env(), names)

    System.put_env(%{
      "DOMAIN" => "family.example.test",
      "RAILS_ENV" => "production",
      "SELF_HOSTED" => "false",
      "MANAGER_URL" => "https://manager.example.test"
    })

    on_exit(fn ->
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
    end)

    :ok
  end

  defp family! do
    [[owner]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('owner@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    [[member]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('member@example.test','{\"locale\":\"fr\"}',now(),now()) RETURNING id"
      )

    [[family]] =
      rows(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Family',$1,now(),now()) RETURNING id",
        [owner]
      )

    {owner, member, family}
  end

  @tag a12f3b_case: "M09a"
  test "family invitation and lapse callbacks deliver native source mail" do
    {owner, member, family} = family!()

    [[invitation]] =
      rows(
        "INSERT INTO family_invitations(email,token,status,family_id,invited_by_id,expires_at,created_at,updated_at) VALUES('member@example.test','synthetic-invitation',0,$1,$2,now()-interval '1 day',now(),now()) RETURNING id",
        [family, owner]
      )

    args = %{"invitation_id" => invitation, "locale" => "en", "event_id" => Ecto.UUID.generate()}
    assert FamilyInvitationWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, invitation_mail}

    assert {:ok, invitation_mail.subject} ==
             Dawarich.I18n.t("fr", "mailers.family.invitation.subject", %{"family" => "Family"})

    assert invitation_mail.text =~
             "https://family.example.test/family/invitations/synthetic-invitation"

    args = %{
      "user_id" => member,
      "family_id" => family,
      "locale" => "en",
      "lapse_at" => "period",
      "event_id" => Ecto.UUID.generate()
    }

    assert FamilyLapseWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, lapse}

    assert {:ok, lapse.subject} ==
             Dawarich.I18n.t("fr", "mailers.family.plan_lapsed.subject", %{"family" => "Family"})

    assert lapse.text =~ "owner@example.test"
    assert lapse.text =~ "manager.example.test"
  end

  @tag a12f3b_case: "M09b"
  test "family lapse source retry does not duplicate delivered mail" do
    {_, member, family} = family!()

    args = %{
      "user_id" => member,
      "family_id" => family,
      "locale" => "en",
      "lapse_at" => "period",
      "event_id" => Ecto.UUID.generate()
    }

    Process.put(:transport_result, {:error, :rejected})
    assert FamilyLapseWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, first}
    [[key, nil]] = rows("SELECT provider_key,delivered_at FROM phoenix.delivery_claims")
    Process.delete(:transport_result)
    assert FamilyLapseWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, second}
    assert first.message_id == second.message_id

    assert rows("SELECT provider_key,delivered_at IS NOT NULL FROM phoenix.delivery_claims") == [
             [key, true]
           ]

    assert FamilyLapseWorker.perform(%Oban.Job{args: args}) == :ok
    refute_received {:mail, _}
  end
end
