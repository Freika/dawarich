defmodule Dawarich.Sync1160ConsentRepo do
  alias Dawarich.Repo
  defdelegate query(sql, params), to: Repo
  defdelegate transaction(fun), to: Repo
  defdelegate rollback(reason), to: Repo
  defdelegate in_transaction?(), to: Repo
  defdelegate get(schema, id, opts), to: Repo

  def query!(sql, params, opts \\ []) do
    result = Repo.query!(sql, params, opts)

    if String.starts_with?(
         sql,
         "SELECT status, expires_at, suggested_duration FROM family_location_requests"
       ) do
      if revoke = Process.delete(:consent_revoke), do: revoke.()
    end

    result
  end
end

defmodule Dawarich.Sync1160ConsentWaitRepo do
  alias Dawarich.ScratchRepo
  defdelegate transaction(fun), to: ScratchRepo
  defdelegate rollback(reason), to: ScratchRepo
  defdelegate in_transaction?(), to: ScratchRepo
  defdelegate get(schema, id, opts), to: ScratchRepo
  defdelegate query(sql, params), to: ScratchRepo

  def query!(sql, params, opts \\ []) do
    if String.starts_with?(
         sql,
         "SELECT status, expires_at, suggested_duration FROM family_location_requests"
       ) do
      if parent = Process.delete(:consent_waiter), do: send(parent, :at_request_lock)
    end

    ScratchRepo.query!(sql, params, opts)
  end
end

defmodule Dawarich.Sync1160ConsentTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Families.Requests}
  alias Dawarich.Test.RailsUser

  setup do
    old = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
    end)

    user = RailsUser.insert!(%{id: 116_031, email: "consent@example.test", plan: 2})

    Repo.query!(
      "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES($1,$1,'Consent',now(),now())",
      [user.id],
      log: false
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$1,0,now(),now())",
      [user.id],
      log: false
    )

    Repo.query!(
      "INSERT INTO family_location_requests(id,family_id,requester_id,target_user_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES($1,$1,$1,$1,0,'24h',now()+interval '1 day',now(),now())",
      [user.id],
      log: false
    )

    %{user: Map.put(Accounts.get(user.id), :timezone, "UTC")}
  end

  test "API consent rechecks membership and Cloud access at final request lock for both decisions",
       %{user: user} do
    for decision <- [:accept, :decline], revoke <- [:membership, :access], web <- [true, false] do
      Repo.query!("UPDATE users SET plan=2 WHERE id=$1", [user.id], log: false)

      Repo.query!(
        "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) SELECT $1,$1,0,now(),now() WHERE NOT EXISTS(SELECT 1 FROM family_memberships WHERE user_id=$1)",
        [user.id],
        log: false
      )

      Process.put(:consent_revoke, fn ->
        if revoke == :membership,
          do:
            Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [user.id], log: false),
          else: Repo.query!("UPDATE users SET plan=1 WHERE id=$1", [user.id], log: false)
      end)

      before = footprint(user.id)

      result =
        Repo.transaction(fn ->
          Requests.respond(
            user,
            decision,
            %{"id" => to_string(user.id), "web" => web},
            DateTime.utc_now(),
            Dawarich.Sync1160ConsentRepo
          )
        end)

      assert {:ok, {:ok, 403, _}} = result
      assert footprint(user.id) == before
    end

    real_lock_wait(user)
  end

  defp real_lock_wait(user) do
    alias Dawarich.ScratchRepo
    Dawarich.JobsCase.reset!(ScratchRepo)
    RailsUser.insert!(%{id: user.id, email: "wait-consent@example.test", plan: 2}, ScratchRepo)

    ScratchRepo.query!(
      "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES($1,$1,'Consent',now(),now())",
      [user.id],
      log: false
    )

    ScratchRepo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$1,0,now(),now())",
      [user.id],
      log: false
    )

    ScratchRepo.query!(
      "INSERT INTO family_location_requests(id,family_id,requester_id,target_user_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES($1,$1,$1,$1,0,'24h',now()+interval '1 day',now(),now())",
      [user.id],
      log: false
    )

    for decision <- [:accept, :decline], revoke <- [:membership, :access] do
      ScratchRepo.query!("UPDATE users SET plan=2 WHERE id=$1", [user.id], log: false)

      ScratchRepo.query!(
        "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) SELECT $1,$1,0,now(),now() WHERE NOT EXISTS(SELECT 1 FROM family_memberships WHERE user_id=$1)",
        [user.id],
        log: false
      )

      parent = self()

      holder =
        Task.async(fn ->
          ScratchRepo.transaction(fn ->
            ScratchRepo.query!(
              "SELECT id FROM family_location_requests WHERE id=$1 FOR UPDATE",
              [user.id],
              log: false
            )

            send(parent, :request_held)

            receive do
              :release -> :ok
            after
              5000 -> raise "request lock release timeout"
            end
          end)
        end)

      assert_receive :request_held, 3000

      waiter =
        Task.async(fn ->
          Process.put(:consent_waiter, parent)

          Requests.web_respond(
            user,
            decision,
            %{"id" => to_string(user.id)},
            DateTime.utc_now(),
            Dawarich.Sync1160ConsentWaitRepo
          )
        end)

      try do
        assert_receive :at_request_lock, 3000

        if revoke == :membership,
          do:
            ScratchRepo.query!("DELETE FROM family_memberships WHERE user_id=$1", [user.id],
              log: false
            ),
          else: ScratchRepo.query!("UPDATE users SET plan=1 WHERE id=$1", [user.id], log: false)

        send(holder.pid, :release)
        assert {:ok, 403, _} = Task.await(waiter, 5000)
        Task.await(holder, 5000)

        assert ScratchRepo.query!(
                 "SELECT status,responded_at FROM family_location_requests WHERE id=$1",
                 [user.id],
                 log: false
               ).rows == [[0, nil]]

        assert ScratchRepo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows ==
                 [[%{}]]
      after
        send(holder.pid, :release)
        Task.shutdown(holder, :brutal_kill)
        Task.shutdown(waiter, :brutal_kill)
      end
    end
  end

  defp footprint(id),
    do:
      Repo.query!(
        "SELECT (SELECT settings FROM users WHERE id=$1),(SELECT status FROM family_location_requests WHERE id=$1),(SELECT count(*) FROM notifications),(SELECT count(*) FROM job_outbox)",
        [id],
        log: false
      ).rows
end
