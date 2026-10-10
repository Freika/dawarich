defmodule Dawarich.FamiliesCommandsTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.{Families, ScratchRepo}
  alias Dawarich.Accounts.{Scope, User}
  alias Dawarich.Test.RailsUser

  @now ~U[2030-01-15 10:00:00Z]
  @opts [repo: ScratchRepo, now: @now, self_hosted: true]

  setup do
    for {id, email} <- [
          {10901, "owner@example.invalid"},
          {10902, "member@example.invalid"},
          {10903, "invitee@example.invalid"}
        ] do
      RailsUser.insert!(
        %{id: id, email: email, plan: 2, settings: %{"timezone" => "UTC"}},
        ScratchRepo
      )
    end

    ScratchRepo.query!(
      "INSERT INTO families(id,name,creator_id,created_at,updated_at) VALUES(10901,'Native family',10901,$1,$1)",
      [DateTime.to_naive(@now)],
      log: false
    )

    for {id, role} <- [{10901, 0}, {10902, 1}] do
      ScratchRepo.query!(
        "INSERT INTO family_memberships(id,family_id,user_id,role,created_at,updated_at) VALUES($1,10901,$1,$2,$3,$3)",
        [id, role, DateTime.to_naive(@now)],
        log: false
      )
    end

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:mail.family_invitation", :oban)
    %{owner: scope(10901), member: scope(10902), invitee: scope(10903)}
  end

  test "scoped family commands reject stale actors and foreign memberships before effects", ctx do
    before = footprint()
    assert {:error, :unauthorized} = Families.update(ctx.member, %{"name" => "forged"}, @opts)
    assert {:error, :not_found} = Families.remove_member(ctx.owner, 999_999, @opts)

    ScratchRepo.query!(
      "UPDATE users SET encrypted_password=$1 WHERE id=10901",
      [String.duplicate("x", 60)],
      log: false
    )

    for call <- [
          fn -> Families.update(ctx.owner, %{"name" => "forged"}, @opts) end,
          fn -> Families.invite(ctx.owner, %{"email" => "new@example.invalid"}, @opts) end,
          fn -> Families.set_sharing(ctx.owner, %{"enabled" => "1"}, @opts) end
        ] do
      assert {:error, :stale_session} = call.()
    end

    assert footprint() == before
  end

  test "family deletion refuses remaining members and owner validation remains in place", ctx do
    assert {:error, :members_present} = Families.delete(ctx.owner, @opts)
    assert {:error, %{errors: [_ | _]}} = Families.update(ctx.owner, %{"name" => ""}, @opts)
    assert {:ok, 10901} = Families.update(ctx.owner, %{"name" => "Changed"}, @opts)
    assert {:ok, %{self?: true}} = Families.remove_member(ctx.member, 10902, @opts)
    assert {:ok, 10901} = Families.delete(ctx.owner, @opts)
    assert rows("SELECT id FROM families WHERE id=10901") == []
  end

  test "failed mail enqueue rolls back invitation and native invalidation", ctx do
    before = footprint()

    assert {:error, :unavailable} =
             Families.invite(
               ctx.owner,
               %{"email" => "new@example.invalid"},
               Keyword.put(@opts, :enqueue, fn repo, _, _ -> repo.rollback(:unavailable) end)
             )

    assert footprint() == before
    refute_receive {:domain_changed, _, _}
  end

  test "concurrent invitation acceptance joins once and cannot exceed family capacity", ctx do
    token = invitation!("invitee@example.invalid")

    tasks =
      for _ <- 1..2,
          do: Task.async(fn -> Families.accept_invitation(ctx.invitee, token, @opts) end)

    results = Enum.map(tasks, &Task.await(&1, 5000))
    assert Enum.count(results, &match?({:ok, 10901}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invitation_processed})) == 1
    assert rows("SELECT count(*) FROM family_memberships WHERE user_id=10903") == [[1]]
    [[membership]] = rows("SELECT id FROM family_memberships WHERE user_id=10903")
    assert {:ok, %{self?: true}} = Families.remove_member(ctx.invitee, membership, @opts)
    for n <- 1..4, do: invitation!("pending#{n}@example.invalid")
    token = invitation!("invitee@example.invalid")

    assert {:error, :family_full} =
             Families.accept_invitation(
               ctx.invitee,
               token,
               Keyword.put(@opts, :self_hosted, false)
             )

    assert rows("SELECT count(*) FROM family_memberships WHERE family_id=10901") == [[2]]
  end

  test "concurrent invitations serialize the final Cloud seat", ctx do
    for n <- 1..2, do: invitation!("pending#{n}@example.invalid")
    parent = self()

    opts =
      @opts
      |> Keyword.put(:repo, Dawarich.Test.FamilyCommandsProbeRepo)
      |> Keyword.put(:self_hosted, false)

    first =
      Task.async(fn ->
        Process.put(:family_command_probe, parent)
        Families.invite(ctx.owner, %{"email" => "first@example.invalid"}, opts)
      end)

    assert_receive {:capacity_checked, pid}, 3000

    second =
      Task.async(fn ->
        Process.put(:family_command_waiter, parent)
        Families.invite(ctx.owner, %{"email" => "second@example.invalid"}, opts)
      end)

    try do
      assert_receive {:family_waiter, backend}, 3000
      waiting = await_waiting(backend)
      send(pid, :release_family)
      assert {:ok, _} = Task.await(first, 5000)
      assert {:error, %{errors: [_ | _]}} = Task.await(second, 5000)
      assert waiting

      assert rows("SELECT count(*) FROM family_invitations WHERE family_id=10901 AND status=0") ==
               [
                 [3]
               ]
    after
      send(pid, :release_family)
      Task.shutdown(first, :brutal_kill)
      Task.shutdown(second, :brutal_kill)
    end
  end

  test "only the current request target may respond before expiry", ctx do
    request!(@now |> DateTime.add(1) |> DateTime.to_naive())

    assert {:error, :unauthorized} =
             Families.respond_location(ctx.owner, 10901, :accept, %{}, @opts)

    ScratchRepo.query!(
      "UPDATE family_location_requests SET target_user_id=10901 WHERE id=10901",
      [],
      log: false
    )

    assert {:error, :unauthorized} =
             Families.respond_location(ctx.member, 10901, :accept, %{}, @opts)

    ScratchRepo.query!(
      "UPDATE family_location_requests SET target_user_id=10902,expires_at=$1 WHERE id=10901",
      [DateTime.to_naive(@now)],
      log: false
    )

    assert {:error, :expired} = Families.respond_location(ctx.member, 10901, :accept, %{}, @opts)
    assert rows("SELECT status FROM family_location_requests WHERE id=10901") == [[0]]

    ScratchRepo.query!(
      "UPDATE family_location_requests SET expires_at=$1 WHERE id=10901",
      [@now |> DateTime.add(1) |> DateTime.to_naive()],
      log: false
    )

    assert {:ok, %{"status" => "accepted"}} =
             Families.respond_location(ctx.member, 10901, :accept, %{"duration" => "1h"}, @opts)
  end

  test "consent history and duration persist independently without location payloads", ctx do
    attrs = %{
      "enabled" => "1",
      "duration" => "6h",
      "share_history" => "1",
      "history_window" => "30d",
      "history_before_sharing" => "0"
    }

    assert {:ok, config} = Families.set_sharing(ctx.member, attrs, @opts)
    assert config["duration"] == "6h"
    assert config["share_history"] == true
    assert config["history_before_sharing"] == false
    assert config["history_window"] == "30d"
    assert config["expires_at"] != nil

    assert {:ok, %{"enabled" => false}} =
             Families.set_sharing(ctx.member, %{"enabled" => "0"}, @opts)

    assert rows(
             "SELECT args->>'kind' FROM oban.oban_jobs WHERE worker='Dawarich.Families.EventsWorker' AND state!='scheduled' ORDER BY id"
           ) == [["consent"], ["consent"], ["consent"], ["consent"]]
  end

  test "finite family consent requests invitations and Cloud access persist durable expiry invalidation",
       ctx do
    assert {:ok, config} =
             Families.set_sharing(ctx.member, %{"enabled" => "1", "duration" => "6h"}, @opts)

    due = Dawarich.Families.Clock.parse(config["expires_at"])

    jobs =
      rows(
        "SELECT args,scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Families.EventsWorker' AND state='scheduled' ORDER BY id"
      )

    assert length(jobs) == 2

    for [args, at] <- jobs do
      assert Enum.sort(Map.keys(args)) == ~w(event_id kind user_id)
      assert args["kind"] == "consent"
      assert args["user_id"] in [10901, 10902]
      assert NaiveDateTime.compare(at, due) == :eq
    end

    assert {:ok, _} = Families.invite(ctx.owner, %{"email" => "expiry@example.invalid"}, @opts)
    assert {:ok, _} = Families.set_sharing(ctx.member, %{"enabled" => "0"}, @opts)
    assert {:ok, _} = Families.request_location(ctx.owner, %{"target_user_id" => "10902"}, @opts)
    until = DateTime.add(@now, 3600) |> DateTime.to_naive()
    ScratchRepo.query!("UPDATE users SET active_until=$1 WHERE id=10901", [until], log: false)

    assert {:ok, _} =
             Families.update(
               ctx.owner,
               %{"name" => "Timed family"},
               Keyword.put(@opts, :self_hosted, false)
             )

    assert rows(
             "SELECT args->>'kind',count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Families.EventsWorker' AND state='scheduled' GROUP BY 1 ORDER BY 1"
           ) == [["consent", 2], ["invitation", 2], ["lapse", 2], ["request", 2]]

    before = footprint()

    assert {:error, :probe} =
             ScratchRepo.transaction(fn ->
               assert {:ok, _} =
                        Families.set_sharing(
                          ctx.member,
                          %{"enabled" => "1", "duration" => "1h"},
                          @opts
                        )

               ScratchRepo.rollback(:probe)
             end)

    assert footprint() == before
  end

  test "family invalidation survives removed membership and rollback emits no event", ctx do
    :ok = Dawarich.Families.Events.subscribe(ctx.member.user.id)
    assert {:ok, _} = Families.remove_member(ctx.owner, 10902, @opts)

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Families.EventsWorker' AND args->>'user_id'='10902'"
      )

    assert Enum.sort(Map.keys(args)) == ~w(event_id kind user_id)
    assert :ok = Dawarich.Families.EventsWorker.run(ScratchRepo, args)
    assert_receive {:domain_changed, 10902, :membership}
    assert :ok = Dawarich.Families.EventsWorker.run(ScratchRepo, args)
    refute_receive {:domain_changed, _, _}
    before = footprint()

    assert {:error, :rollback_probe} =
             ScratchRepo.transaction(fn ->
               assert {:ok, _} = Families.update(ctx.owner, %{"name" => "rolled back"}, @opts)
               ScratchRepo.rollback(:rollback_probe)
             end)

    assert footprint() == before
    refute_receive {:domain_changed, _, _}
  end

  test "family commands re-admit original identity after taking locks", ctx do
    parent = self()
    opts = Keyword.put(@opts, :repo, Dawarich.Test.FamilyCommandsProbeRepo)

    task =
      Task.async(fn ->
        Process.put(:family_recheck_probe, parent)
        Families.update(ctx.owner, %{"name" => "stale update"}, opts)
      end)

    try do
      assert_receive {:family_locked, pid}, 3000

      ScratchRepo.query!(
        "UPDATE users SET encrypted_password=$1 WHERE id=10901",
        [String.duplicate("x", 60)],
        log: false
      )

      send(pid, :release_family)
      assert {:error, :stale_session} = Task.await(task, 5000)
      assert rows("SELECT name FROM families WHERE id=10901") == [["Native family"]]
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    after
      send(task.pid, :release_family)
      Task.shutdown(task, :brutal_kill)
    end
  end

  test "family creation invitation cancellation and location requests use scoped validation",
       ctx do
    assert {:error, %{errors: [_ | _]}} = Families.create(ctx.invitee, %{"name" => ""}, @opts)
    assert {:ok, created} = Families.create(ctx.invitee, %{"name" => "  New family  "}, @opts)
    assert rows("SELECT name FROM families WHERE id=$1", [created]) == [["New family"]]
    assert {:ok, _} = Families.delete(ctx.invitee, @opts)

    assert {:ok, invitation} =
             Families.invite(ctx.owner, %{"email" => "new@example.invalid"}, @opts)

    assert {:error, :unauthorized} = Families.cancel_invitation(ctx.member, invitation, @opts)
    assert {:ok, ^invitation} = Families.cancel_invitation(ctx.owner, invitation, @opts)
    assert rows("SELECT status FROM family_invitations WHERE id=$1", [invitation]) == [[3]]

    assert {:ok, %{"request" => %{"target_user_id" => 10902}}} =
             Families.request_location(ctx.owner, %{"target_user_id" => "10902"}, @opts)

    assert {:error, %{status: 429}} =
             Families.request_location(ctx.owner, %{"target_user_id" => "10902"}, @opts)

    assert {:error, :invalid_input} =
             Families.respond_location(ctx.member, 10901, :forged, %{}, @opts)
  end

  defp scope(id), do: Scope.for_user(ScratchRepo.get!(User, id, log: false), "en")

  defp footprint,
    do:
      rows(
        "SELECT (SELECT jsonb_agg(name ORDER BY id) FROM families), (SELECT count(*) FROM family_invitations), (SELECT count(*) FROM family_memberships), (SELECT count(*) FROM notifications), (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM oban.oban_jobs)"
      )

  defp invitation!(email) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(20), padding: false)

    ScratchRepo.query!(
      "INSERT INTO family_invitations(family_id,email,token,status,invited_by_id,expires_at,created_at,updated_at) VALUES(10901,$1,$2,0,10901,$3,$4,$4)",
      [email, token, @now |> DateTime.add(3600) |> DateTime.to_naive(), DateTime.to_naive(@now)],
      log: false
    )

    token
  end

  defp request!(expiry) do
    ScratchRepo.query!(
      "INSERT INTO family_location_requests(id,requester_id,target_user_id,family_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES(10901,10901,10902,10901,0,'24h',$1,$2,$2)",
      [expiry, DateTime.to_naive(@now)],
      log: false
    )
  end

  defp await_waiting(backend) do
    deadline = System.monotonic_time(:millisecond) + 3000
    wait(backend, deadline)
  end

  defp wait(backend, deadline) do
    case ScratchRepo.query!(
           "SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1",
           [backend],
           log: false
         ).rows do
      [["Lock"]] ->
        true

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          wait(backend, deadline)
        else
          false
        end
    end
  end
end
