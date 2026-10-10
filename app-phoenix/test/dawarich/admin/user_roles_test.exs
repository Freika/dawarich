defmodule Dawarich.Admin.UserRolesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Users
  alias Dawarich.Admin.UserRoles
  alias Dawarich.{Accounts, I18n, Repo}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Application.get_env(:dawarich, Users)

    Application.put_env(:dawarich, Users, %{
      env: %{"SELF_HOSTED" => "true"}
    })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Users, previous),
        else: Application.delete_env(:dawarich, Users)
    end)

    RailsUser.insert!(%{
      id: 15101,
      email: "a10b-roles-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    RailsUser.insert!(%{
      id: 15102,
      email: "a10b-roles-deleted@example.invalid",
      admin: true,
      deleted_at: ~N[2026-10-04 10:00:00]
    })

    %{target: Accounts.get(15101), context: %{self_hosted: true, oidc: false}}
  end

  test "refuses sole admin zero role or nonactive raw status with Rails alerts", c do
    assert Code.ensure_loaded?(UserRoles), "last admin guard must exist"
    before = snapshot()

    for locale <- ["en", "de"],
        {params, key} <- [
          {%{"admin" => "0"}, "cannot_remove_last_admin_role"},
          {%{"admin" => 0, "status" => "inactive"}, "cannot_remove_last_admin_role"},
          {%{"status" => "inactive"}, "cannot_disable_last_admin"},
          {%{"status" => 1}, "cannot_disable_last_admin"},
          {%{"status" => nil}, "cannot_disable_last_admin"},
          {%{"status" => "invalid"}, "cannot_disable_last_admin"}
        ] do
      {:ok, message} = I18n.t(locale, "controllers.settings.users." <> key)
      assert {:blocked, ^message} = UserRoles.guard(c.target, params, Repo, locale)
    end

    oracle = File.read!("test/fixtures/admin_mutations/last_admin_role.json") |> Jason.decode!()

    assert {:blocked, oracle["flash"]["alert"]} ==
             UserRoles.guard(c.target, %{"admin" => "0"}, Repo, "en")

    assert oracle["status"] == 302
    assert snapshot() == before

    Repo.query!("UPDATE users SET deleted_at=NULL WHERE id=15102", [], log: false)
    assert :ok = UserRoles.guard(c.target, %{"admin" => "0", "status" => "inactive"}, Repo, "en")

    assert :ok =
             UserRoles.guard(%{c.target | admin: false}, %{"status" => "inactive"}, Repo, "en")
  end

  test "does not impose stronger role rules and rechecks a demoted actor", c do
    assert Code.ensure_loaded?(UserRoles), "last admin guard must exist"

    for params <- [
          %{},
          %{"admin" => "false"},
          %{"admin" => false},
          %{"admin" => "off"},
          %{"admin" => nil},
          %{"status" => "active"}
        ] do
      assert :ok = UserRoles.guard(c.target, params, Repo, "en")
    end

    assert {:blocked, _} = UserRoles.guard(c.target, %{"status" => 1}, Repo, "en")

    scope = Scope.for_user(c.target, "en")
    assert {:ok, 15101} = Users.update(scope, c.target.id, %{})
    Repo.query!("UPDATE users SET admin=false WHERE id=15101", [], log: false)
    before = snapshot()
    assert Users.update(scope, c.target.id, %{}) == {:error, :unauthorized}
    assert snapshot() == before
  end

  defp snapshot do
    Repo.query!(
      "SELECT (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM users u),(SELECT count(*) FROM job_outbox),(SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows
  end

  test "the admin-row lock bounds only its own wait and restores the lock timeout" do
    timeout = fn -> Repo.query!("SELECT current_setting('lock_timeout')", [], log: false).rows end

    Repo.transaction(fn ->
      before = timeout.()
      assert UserRoles.lock(Repo) == :ok
      assert timeout.() == before
      refute timeout.() == [["100ms"]]
    end)
  end
end
