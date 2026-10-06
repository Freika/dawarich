defmodule Dawarich.A12f3bE07Test do
  use Dawarich.JobsCase

  alias Dawarich.Families.{AutoCreateWorker, MemberSyncWorker}
  alias Dawarich.Families.{InvitationCleanupWorker, LocationRequestExpiryWorker}
  alias Dawarich.Jobs.{Dispatch, Drain, Ownership, Processed}
  alias Dawarich.Mail.{FamilyInvitationWorker, FamilyLapseWorker}
  alias Dawarich.Geocoding.HookRepo

  @now ~U[2026-10-06 12:00:00.000000Z]
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)

    for {key, value} <- [{"SELF_HOSTED", "false"}, {"DOMAIN", "family.example.test"}] do
      previous = System.get_env(key)
      System.put_env(key, value)

      on_exit(fn ->
        if previous, do: System.put_env(key, previous), else: System.delete_env(key)
      end)
    end

    on_exit(&HookRepo.clear_hook/0)
    Ownership.put!(ScratchRepo, "command:mail.family_lapse", :oban)
    :ok
  end

  @tag a12f3b_case: "E07a"
  test "E07 native owner accepts every retained argument and continuation shape" do
    owner = user!(2, %{"locale" => "de"})

    event =
      outbox!(
        command_type: "families.auto_create",
        payload: %{
          "user_id" => Integer.to_string(owner),
          "time_zone" => "Asia/Tokyo"
        },
        scheduled_at: DateTime.add(@now, 60)
      )

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now) == %{}
    assert Drain.status(ScratchRepo).counts.pending_outbox == 1

    assert %{dispatched: 1} =
             Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(@now, 60))

    assert [[job, %{"user_id" => ^owner, "event_id" => ^event} = args]] =
             rows("SELECT id,args FROM oban.oban_jobs")

    assert :ok = AutoCreateWorker.run(ScratchRepo, args, now: @now)
    assert :ok = AutoCreateWorker.run(ScratchRepo, args, now: @now)
    finish(job)
    assert Processed.done?(ScratchRepo, event)

    assert [[family, "Meine Familie"]] =
             rows("SELECT id,name FROM families WHERE creator_id=$1", [owner])

    assert rows(
             "SELECT settings #>> '{family,location_sharing,started_at}' FROM users WHERE id=$1",
             [owner]
           ) ==
             [["2026-10-06T21:00:00+09:00"]]

    assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [owner]) == [[1]]

    member = user!(0, %{"locale" => "fr"})
    membership!(family, member)
    rows("UPDATE users SET active_until=$2 WHERE id=$1", [owner, ~N[2026-10-05 12:00:00.000000]])

    sync_event =
      outbox!(
        command_type: "families.member_sync",
        payload: %{
          "family_id" => family,
          "locale" => "de",
          "time_zone" => "Tokyo"
        },
        scheduled_at: @now
      )

    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now)

    assert [[sync_job, sync_args]] =
             rows("SELECT id,args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [sync_event])

    assert :ok = MemberSyncWorker.run(ScratchRepo, sync_args, now: @now)
    assert :ok = MemberSyncWorker.run(ScratchRepo, sync_args, now: @now)
    finish(sync_job)
    assert rows("SELECT plan,status FROM users WHERE id=$1", [member]) == [[0, 0]]

    assert [[%{"locale" => "de", "lapse_at" => "2026-10-05T12:00:00Z"}]] =
             rows("SELECT payload FROM job_outbox WHERE command_type='mail.family_lapse'")

    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now)

    assert [[mail_job, mail_args]] =
             rows("SELECT id,args FROM oban.oban_jobs WHERE state <> 'completed'")

    Process.put(:transport_result, {:error, :synthetic_smtp_failure})

    assert {:error, :synthetic_smtp_failure} =
             FamilyLapseWorker.perform(%Oban.Job{args: mail_args})

    assert_received {:mail, _}

    assert rows("SELECT settings #>> '{family,plan_lapse_notified_at}' FROM users WHERE id=$1", [
             member
           ]) == [[nil]]

    Process.delete(:transport_result)
    assert :ok = FamilyLapseWorker.perform(%Oban.Job{args: mail_args})
    assert_received {:mail, %{to: email, subject: subject}}
    assert email == email(member)

    assert {:ok, ^subject} =
             Dawarich.I18n.t("fr", "mailers.family.plan_lapsed.subject", %{
               "family" => "Meine Familie"
             })

    assert :ok = FamilyLapseWorker.perform(%Oban.Job{args: mail_args})
    refute_received {:mail, _}
    finish(mail_job)

    invitation = invitation!(family, owner, 0, DateTime.add(@now, 86_400), @now)

    invite_event =
      outbox!(
        command_type: "mail.family_invitation",
        payload: %{"invitation_id" => invitation, "locale" => "es"},
        scheduled_at: @now
      )

    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now)

    assert [[invite_job, invite_args]] =
             rows("SELECT id,args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [invite_event])

    assert :ok = FamilyInvitationWorker.perform(%Oban.Job{args: invite_args})
    assert_received {:mail, %{text: text}}
    assert text =~ "https://family.example.test/family/invitations/"
    assert :ok = FamilyInvitationWorker.perform(%Oban.Job{args: invite_args})
    refute_received {:mail, _}
    finish(invite_job)

    expiry = request!(family, owner, member, 0, @now)
    accepted = request!(family, owner, member, 1, DateTime.add(@now, -1))
    Ownership.put!(ScratchRepo, LocationRequestExpiryWorker.key(), :oban)
    assert :ok = LocationRequestExpiryWorker.run(ScratchRepo, DateTime.to_naive(@now))

    assert rows("SELECT status,updated_at FROM family_location_requests WHERE id=$1", [expiry]) ==
             [[3, DateTime.to_naive(@now)]]

    assert rows("SELECT status FROM family_location_requests WHERE id=$1", [accepted]) == [[1]]

    boundary = invitation!(family, owner, 0, @now, @now)

    stale =
      invitation!(family, owner, 0, DateTime.add(@now, -1), DateTime.add(@now, -31 * 86_400))

    Ownership.put!(ScratchRepo, InvitationCleanupWorker.key(), :oban)
    assert :ok = InvitationCleanupWorker.run(ScratchRepo, DateTime.to_naive(@now))
    assert rows("SELECT status FROM family_invitations WHERE id=$1", [boundary]) == [[0]]
    assert rows("SELECT id FROM family_invitations WHERE id=$1", [stale]) == []
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert Drain.status(ScratchRepo).counts.pending_outbox == 0
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0

    for worker <- [AutoCreateWorker, MemberSyncWorker],
        do: assert(worker.args_from_command(2, %{}) == {:error, "unsupported_version"})

    for bad <- [nil, [], %{}, "invalid", "9223372036854775808"] do
      assert {:error, "invalid_payload"} =
               AutoCreateWorker.args_from_command(1, %{"user_id" => bad, "time_zone" => "UTC"})
    end

    for id <- [-1, user!(1, %{})] do
      assert :ok =
               AutoCreateWorker.run(
                 ScratchRepo,
                 %{"user_id" => id, "time_zone" => "UTC", "event_id" => Ecto.UUID.generate()},
                 now: @now
               )
    end
  end

  @tag a12f3b_case: "E07b"
  test "E07 source accepted chain remains visible until all children settle" do
    owner = user!(2, %{})

    event =
      outbox!(
        command_type: "families.auto_create",
        payload: %{"user_id" => owner, "time_zone" => "UTC"},
        scheduled_at: @now
      )

    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now)

    [[auto_job, args]] =
      rows("SELECT id,args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [event])

    assert_raise RuntimeError, "sharing unavailable", fn ->
      AutoCreateWorker.run(ScratchRepo, args,
        now: @now,
        hook: fn
          :shared -> raise "sharing unavailable"
          _ -> :ok
        end
      )
    end

    refute Processed.done?(ScratchRepo, event)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
    assert rows("SELECT id FROM families WHERE creator_id=$1", [owner]) == []
    assert :ok = AutoCreateWorker.run(ScratchRepo, args, now: @now)
    finish(auto_job)
    [[family]] = rows("SELECT id FROM families WHERE creator_id=$1", [owner])
    member = user!(1, %{})
    membership!(family, member)
    rows("UPDATE users SET active_until=$2 WHERE id=$1", [owner, ~N[2026-10-05 12:00:00.000000]])

    payload = %{
      "family_id" => Integer.to_string(family),
      "locale" => "de",
      "time_zone" => "Asia/Tokyo"
    }

    assert {:ok, decoded} = MemberSyncWorker.args_from_command(1, payload)
    parent = outbox!(command_type: "families.member_sync", payload: payload, scheduled_at: @now)
    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now)

    [[sync_job, sync]] =
      rows("SELECT id,args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [parent])

    assert sync == Map.put(decoded, "event_id", parent)

    HookRepo.set_hook(fn sql, _ ->
      if String.starts_with?(sql, "INSERT INTO public.job_outbox"),
        do: raise("mail child unavailable")
    end)

    assert_raise RuntimeError, "mail child unavailable", fn ->
      MemberSyncWorker.run(HookRepo, sync, now: @now)
    end

    refute Processed.done?(ScratchRepo, parent)
    assert rows("SELECT plan FROM users WHERE id=$1", [member]) == [[1]]
    assert rows("SELECT count(*) FROM job_outbox WHERE state='pending'") == [[0]]
    HookRepo.clear_hook()
    assert :ok = MemberSyncWorker.run(ScratchRepo, sync, now: @now)
    assert Processed.done?(ScratchRepo, parent)
    assert :ok = MemberSyncWorker.run(ScratchRepo, sync, now: @now)
    finish(sync_job)
    assert Drain.status(ScratchRepo).counts.pending_outbox == 1
    assert "pending_outbox" in Drain.status(ScratchRepo).shutdown_reasons
    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban, now: @now)
    assert [[job, child]] = rows("SELECT id,args FROM oban.oban_jobs WHERE state <> 'completed'")
    assert Drain.status(ScratchRepo).shutdown == "BLOCKED"
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    Process.put(:transport_result, {:error, :synthetic_smtp_failure})
    assert {:error, :synthetic_smtp_failure} = FamilyLapseWorker.perform(%Oban.Job{args: child})
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    Process.delete(:transport_result)
    assert :ok = FamilyLapseWorker.perform(%Oban.Job{args: child})
    finish(job)
    assert Drain.status(ScratchRepo).counts.pending_outbox == 0
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  defp user!(plan, settings) do
    [[id]] =
      rows(
        "INSERT INTO users(email,plan,status,settings,active_until,created_at,updated_at) VALUES($1,$2,0,$3,$4,now(),now()) RETURNING id",
        [
          "e07-#{System.unique_integer([:positive])}@example.test",
          plan,
          settings,
          ~N[2026-10-07 12:00:00.000000]
        ]
      )

    id
  end

  defp membership!(family, member),
    do:
      rows(
        "INSERT INTO family_memberships(family_id,user_id,created_at,updated_at) VALUES($1,$2,now(),now())",
        [family, member]
      )

  defp email(id), do: rows("SELECT email FROM users WHERE id=$1", [id]) |> hd() |> hd()

  defp finish(id),
    do: rows("UPDATE oban.oban_jobs SET state='completed',completed_at=now() WHERE id=$1", [id])

  defp invitation!(family, owner, status, expires, updated) do
    [[id]] =
      rows(
        "INSERT INTO family_invitations(family_id,invited_by_id,email,token,status,expires_at,created_at,updated_at) VALUES($1,$2,'invitee@example.test',$3,$4,$5,$6,$6) RETURNING id",
        [
          family,
          owner,
          Ecto.UUID.generate(),
          status,
          DateTime.to_naive(expires),
          DateTime.to_naive(updated)
        ]
      )

    id
  end

  defp request!(family, owner, member, status, expires) do
    [[id]] =
      rows(
        "INSERT INTO family_location_requests(family_id,requester_id,target_user_id,status,expires_at,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$6) RETURNING id",
        [
          family,
          owner,
          member,
          status,
          DateTime.to_naive(expires),
          DateTime.to_naive(DateTime.add(@now, -60))
        ]
      )

    id
  end
end
