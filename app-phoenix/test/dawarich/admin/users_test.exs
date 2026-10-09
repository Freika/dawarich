defmodule Dawarich.Admin.UsersLockProbeRepo do
  alias Dawarich.ScratchRepo
  defdelegate transaction(fun), to: ScratchRepo
  defdelegate rollback(reason), to: ScratchRepo
  defdelegate in_transaction?(), to: ScratchRepo
  defdelegate one(query, opts), to: ScratchRepo

  def query!(sql, params, opts \\ []) do
    result = ScratchRepo.query!(sql, params, opts)

    if String.starts_with?(sql, "SELECT id FROM users WHERE admin") do
      if parent = Process.delete(:admin_lock_probe) do
        send(parent, :admins_locked)

        receive do
          :demote -> :ok
        end
      end
    end

    result
  end
end

defmodule Dawarich.Admin.UsersTest do
  use Dawarich.JobsCase
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Users
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    start_oban(UsersDomainOban, repo: Repo)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    previous_rails = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    previous_config = Application.get_env(:dawarich, Users)
    Application.put_env(:dawarich, Users, %{oban: UsersDomainOban})
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous_rails,
        do: System.put_env("DAWARICH_RAILS", previous_rails),
        else: System.delete_env("DAWARICH_RAILS")

      if previous_config,
        do: Application.put_env(:dawarich, Users, previous_config),
        else: Application.delete_env(:dawarich, Users)

      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    Dawarich.State.put_registration_enabled(Repo, true)
    RailsUser.insert!(%{id: 10711, email: "users-admin@example.invalid", admin: true})

    RailsUser.insert!(%{
      id: 10712,
      email: "users-target@example.invalid",
      api_key: "synthetic-target-key"
    })

    %{scope: Scope.for_user(Accounts.get(10711), "en")}
  end

  test "users facade rejects demoted deleted and stale-salt scopes", %{scope: scope} do
    assert {:ok, %{rows: rows}} = Users.list(scope, %{})
    assert length(rows) == 2
    assert {:ok, %{user: user, details: details, counts: counts}} = Users.get(scope, 10712, :show)
    assert user.api_key == "synthetic-target-key"
    refute inspect(user) =~ "synthetic-target-key"
    refute Map.has_key?(details, :api_key)
    assert counts == %{"tracks" => 0, "imports" => 0, "exports" => 0, "areas" => 0}
    assert {:ok, %{id: 10712} = edit} = Users.get(scope, "10712", :edit)
    assert Map.keys(edit) |> Enum.sort() == [:admin, :email, :id, :status]

    for {sql, reason} <- [
          {"admin=false", :unauthorized},
          {"admin=true, deleted_at=now()", :stale_session},
          {"deleted_at=NULL, encrypted_password='changed-synthetic-password-salt'",
           :stale_session}
        ] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=10711", [], log: false)
      assert Users.list(scope, %{}) == {:error, reason}
      assert Users.get(scope, 10712, :show) == {:error, reason}
      assert Users.get(scope, 10712, :edit) == {:error, reason}
    end
  end

  test "mutations refuse actor revocation between socket hook and context call", %{scope: scope} do
    for {sql, reason} <- [
          {"admin=false", :unauthorized},
          {"admin=true, encrypted_password='changed-synthetic-password-salt'", :stale_session},
          {"deleted_at=now()", :stale_session}
        ] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=10711", [], log: false)
      before = footprint()

      assert Users.create(scope, %{
               "email" => "new@example.invalid",
               "password" => "synthetic-password"
             }) == {:error, reason}

      assert Users.update(scope, 10712, %{"email" => "changed@example.invalid"}) ==
               {:error, reason}

      assert Users.delete(scope, 10712) == {:error, reason}

      assert Users.update_registration(scope, %{"registration_enabled" => "0"}) ==
               {:error, reason}

      assert Users.rotate_api_key(scope, 10712) == {:error, reason}
      assert Users.send_password_reset(scope, 10712) == {:error, reason}
      assert footprint() == before
    end
  end

  test "user mutations preserve validation blank passwords role rules and registration casts", %{
    scope: scope
  } do
    assert {:error, {:validation, _}} = Users.create(scope, %{"email" => "bad", "password" => ""})

    assert {:ok, id} =
             Users.create(scope, %{
               "email" => " NEW@example.invalid ",
               "password" => "synthetic-password"
             })

    assert Users.update(scope, id, nil) == {:error, :invalid_input}

    assert Users.create(scope, %{"email" => [], "password" => "synthetic-password"}) ==
             {:error, :invalid_input}

    assert Users.get(scope, "999999999999999999999999", :edit) == {:error, :not_found}
    user = Accounts.get(id)
    assert user.email == "new@example.invalid" and user.status == 1
    before = user.encrypted_password
    assert {:ok, ^id} = Users.update(scope, id, %{"email" => user.email, "password" => ""})
    assert Accounts.get(id).encrypted_password == before
    assert {:error, {:blocked, _}} = Users.update(scope, scope.user.id, %{"admin" => "0"})
    assert Users.update(scope, -1, %{}) == {:error, :not_found}

    for {source, value} <- [{"0", false}, {"1", true}, {nil, nil}] do
      assert {:ok, ^value} = Users.update_registration(scope, %{"registration_enabled" => source})

      assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
               [[value]]
    end
  end

  test "delete enqueues once and rolls back soft deletion on enqueue failure", %{scope: scope} do
    assert Users.delete(scope, scope.user.id) == {:error, :self}

    Repo.query!(
      "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES(10712,10712,'Synthetic family',now(),now())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(10712,10712,0,now(),now()),(10712,10711,1,now(),now())",
      [],
      log: false
    )

    assert Users.delete(scope, 10712) == {:error, :cannot_delete_account}
    Repo.query!("DELETE FROM family_memberships WHERE user_id=10711", [], log: false)
    Dawarich.Jobs.Ownership.put!(Repo, "command:users.destroy", :oban)

    Application.put_env(:dawarich, Users, %{
      enqueue_destroy: fn id ->
        :ok = Dawarich.Users.DestroyWorker.enqueue(Repo, id)
        {:error, :failed}
      end
    })

    assert Users.delete(scope, 10712) == {:error, :unavailable}
    assert Accounts.get(10712) != nil
    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[0]]
    Application.put_env(:dawarich, Users, %{})
    assert {:ok, :scheduled} = Users.delete(scope, "10712")
    assert Users.delete(scope, 10712) == {:error, :not_found}

    assert Repo.query!("SELECT command_type,payload FROM job_outbox", [], log: false).rows == [
             ["users.destroy", %{"user_id" => 10712}]
           ]
  end

  test "target reset rollback leaves no digest or sealed mail", %{scope: scope} do
    Application.put_env(:dawarich, Users, %{
      oban: UsersDomainOban,
      enqueue: fn notification ->
        :ok = Dawarich.Auth.Recovery.MailWorker.enqueue(notification, UsersDomainOban)
        {:error, :failed}
      end
    })

    assert Users.send_password_reset(scope, 10712) == {:error, :unavailable}

    assert Repo.query!("SELECT reset_password_token FROM users WHERE id=10712", [], log: false).rows ==
             [[nil]]

    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs", [], log: false).rows == [[0]]
    Application.put_env(:dawarich, Users, %{oban: UsersDomainOban})
    assert {:ok, 10712} = Users.send_password_reset(%{scope | locale: "de"}, 10712)
    assert [[args]] = Repo.query!("SELECT args FROM oban.oban_jobs", [], log: false).rows
    assert args["user_id"] == 10712 and args["locale"] == "de"
    assert is_binary(args["sealed"])

    assert Repo.query!("SELECT reset_password_token FROM users WHERE id=10711", [], log: false).rows ==
             [[nil]]
  end

  test "target rotation never changes actor credentials", %{scope: scope} do
    before = Accounts.get(scope.user.id)
    assert {:ok, 10712} = Users.rotate_api_key(scope, 10712)
    assert Accounts.get(scope.user.id) == before
    assert Accounts.get(10712).api_key != "synthetic-target-key"
  end

  test "rotated target key is refused by the API", %{scope: scope} do
    assert api_status("synthetic-target-key") == 200
    assert {:ok, 10712} = Users.rotate_api_key(scope, 10712)
    assert api_status("synthetic-target-key") == 401
    assert api_status(Accounts.get(10712).api_key) == 200
  end

  test "OIDC instance refuses user mutations with the OIDC alert", %{scope: scope} do
    Application.put_env(:dawarich, Users, %{
      env: %{
        "SELF_HOSTED" => "true",
        "OIDC_CLIENT_ID" => "synthetic",
        "OIDC_CLIENT_SECRET" => "synthetic"
      }
    })

    before = footprint()
    assert {:ok, _} = Users.list(scope, %{})
    assert {:ok, _} = Users.get(scope, 10712, :show)
    assert Users.create(scope, %{}) == {:error, :oidc}
    assert Users.update(scope, 10712, %{}) == {:error, :oidc}
    assert Users.delete(scope, 10712) == {:error, :oidc}
    assert Users.update_registration(scope, %{}) == {:error, :oidc}
    assert Users.rotate_api_key(scope, 10712) == {:error, :oidc}
    assert Users.send_password_reset(scope, 10712) == {:error, :oidc}
    assert footprint() == before
  end

  test "delete guard holds under concurrent delete and demote", %{scope: scope} do
    for {id, admin} <- [{10711, true}, {10712, true}] do
      RailsUser.insert!(
        %{id: id, email: "locking-#{id}@example.invalid", admin: admin},
        ScratchRepo
      )
    end

    Repo.query!("UPDATE users SET admin=true WHERE id=10712", [], log: false)
    Application.put_env(:dawarich, Users, %{repo: Dawarich.Admin.UsersLockProbeRepo})
    parent = self()

    holder =
      Task.async(fn ->
        Process.put(:admin_lock_probe, parent)
        Users.update(scope, 10711, %{"admin" => "0"})
      end)

    assert_receive :admins_locked
    assert {:ok, %{id: 10712}} = Users.get(scope, 10712, :edit)
    contender = Task.async(fn -> Users.delete(scope, 10712) end)
    assert Task.await(contender, 5000) == {:error, :unauthorized}
    send(holder.pid, :demote)
    assert {:ok, 10711} = Task.await(holder, 5000)
    assert Users.delete(scope, 10712) == {:error, :last_admin}

    assert ScratchRepo.query!("SELECT count(*) FROM users WHERE admin AND deleted_at IS NULL", [],
             log: false
           ).rows == [[1]]
  end

  defp footprint do
    Repo.query!(
      "SELECT (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM users u), (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM oban.oban_jobs), (SELECT enabled FROM phoenix.registration_setting)",
      [],
      log: false
    ).rows
  end

  defp api_status(key) do
    Plug.Test.conn(:get, "/api/v1/points")
    |> Plug.Conn.put_req_header("authorization", "Bearer " <> key)
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
    |> Map.fetch!(:status)
  end
end
