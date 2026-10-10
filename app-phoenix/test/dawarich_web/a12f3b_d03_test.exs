defmodule DawarichWeb.A12f3bD03Test do
  use Dawarich.JobsCase
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Users

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    start_oban(AdminRecoveryOban)
    previous = Application.get_env(:dawarich, Users)
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Users, previous),
        else: Application.delete_env(:dawarich, Users)

      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    for repo <- [Repo, ScratchRepo], {id, admin} <- [{33001, true}, {33002, false}] do
      RailsUser.insert!(
        %{
          id: id,
          email: "admin-user-#{id}@example.invalid",
          admin: admin,
          settings: %{"timezone" => "UTC", "locale" => "de"}
        },
        repo
      )
    end

    config = %{
      repo: ScratchRepo,
      oban: AdminRecoveryOban,
      env: %{"SELF_HOSTED" => "true"}
    }

    Application.put_env(:dawarich, Users, config)
    %{scope: Scope.for_user(Accounts.get(33001), "de"), config: config}
  end

  @tag a12f3b_case: "D03a"
  test "admin user forms preserve last admin and native deletion producer", c do
    for params <- [%{"admin" => "0"}, %{"status" => "disabled"}] do
      assert {:error, {:blocked, _}} = Users.update(c.scope, 33001, params)
    end

    assert Users.delete(c.scope, 33001) == {:error, :self}

    enqueue = fn id ->
      ScratchRepo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'users.destroy',1,$1,'{}',$2,now())",
        [%{"user_id" => id}, id],
        log: false
      )

      :ok
    end

    rows(
      "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES(33001,33002,'Synthetic family',now(),now())"
    )

    rows(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(33001,33002,0,now(),now()),(33001,33001,1,now(),now())"
    )

    Application.put_env(:dawarich, Users, Map.put(c.config, :enqueue_destroy, enqueue))
    assert Users.delete(c.scope, 33002) == {:error, :cannot_delete_account}
    assert rows("SELECT deleted_at FROM users WHERE id=33002") == [[nil]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    rows("DELETE FROM family_memberships WHERE user_id=33001")

    assert {:ok, :scheduled} = Users.delete(c.scope, 33002)
    assert rows("SELECT deleted_at IS NOT NULL FROM users WHERE id=33002") == [[true]]

    assert rows("SELECT command_type,payload FROM job_outbox") == [
             ["users.destroy", %{"user_id" => 33002}]
           ]

    assert Users.delete(c.scope, 33002) == {:error, :not_found}
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]

    assert Users.delete(Scope.for_user(Accounts.get(33002), "de"), 33001) ==
             {:error, :unauthorized}

    assert rows("SELECT deleted_at IS NULL FROM users WHERE id=33001") == [[true]]

    RailsUser.insert!(%{id: 33003, email: "rollback-target@example.invalid"}, ScratchRepo)

    Application.put_env(
      :dawarich,
      Users,
      Map.put(c.config, :enqueue_destroy, fn _ -> {:error, :failed} end)
    )

    assert Users.delete(c.scope, 33003) == {:error, :unavailable}
    assert rows("SELECT deleted_at IS NULL FROM users WHERE id=33003") == [[true]]
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end

  @tag a12f3b_case: "D03b"
  test "admin password reset invokes native mail under correct locale", c do
    assert {:ok, 33002} = Users.send_password_reset(c.scope, 33002)
    assert [[digest]] = rows("SELECT reset_password_token FROM users WHERE id=33002")
    assert is_binary(digest)

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               inspect(Dawarich.Auth.Recovery.MailWorker)
             ])

    assert args["digest"] == digest
    assert args["locale"] == "de"
    assert args["user_id"] == 33002
    assert args["kind"] == "reset_password_instructions"
    refute Jason.encode!(args) =~ "reset_password_token"

    assert Users.send_password_reset(c.scope, 33999) == {:error, :not_found}

    assert Users.send_password_reset(Scope.for_user(Accounts.get(33002), "de"), 33001) ==
             {:error, :unauthorized}

    Application.put_env(:dawarich, Users, %{c.config | env: %{"SELF_HOSTED" => "false"}})
    assert Users.send_password_reset(c.scope, 33001) == {:error, :cloud}
    Application.put_env(:dawarich, Users, c.config)

    assert rows("SELECT reset_password_token FROM users WHERE id=33001") == [[nil]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]

    Application.put_env(
      :dawarich,
      Users,
      Map.put(c.config, :enqueue, fn _ -> {:error, :smtp} end)
    )

    assert Users.send_password_reset(c.scope, 33001) == {:error, :unavailable}
    assert rows("SELECT reset_password_token FROM users WHERE id=33001") == [[nil]]
  end

  @tag a12f3b_case: "D03c"
  test "native admin refusals preserve typed reasons and no effects", c do
    for {actor, env, reason} <- [
          {33002, %{"SELF_HOSTED" => "true"}, :unauthorized},
          {33001, %{"SELF_HOSTED" => "false"}, :cloud}
        ] do
      Application.put_env(:dawarich, Users, %{c.config | env: env})
      scope = Scope.for_user(Accounts.get(actor), "de")

      assert Users.create(scope, %{
               "email" => "refused@example.invalid",
               "password" => "synthetic-admin-password"
             }) == {:error, reason}

      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, locale: "de", flash: %{}}}
      refused = DawarichWeb.AdminUI.refuse(socket, reason)
      assert refused.redirected == {:redirect, %{to: "/", status: 302}}

      assert refused.assigns.flash["alert"] ==
               DawarichWeb.Translate.t(
                 "de",
                 "controllers.application.you_are_not_authorized_to_perform_this_action",
                 %{}
               )
    end

    assert rows("SELECT count(*) FROM users") == [[2]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end
end
