defmodule Dawarich.Admin.AccessTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.{Access, OperatorGrant}
  alias Dawarich.Test.RailsUser

  @self_hosted %{"SELF_HOSTED" => "true"}
  @cloud %{"SELF_HOSTED" => "false"}
  @oidc %{"SELF_HOSTED" => "true", "OIDC_CLIENT_ID" => "synthetic", "OIDC_CLIENT_SECRET" => "x"}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    RailsUser.insert!(%{
      id: 10701,
      email: "access-admin@example.invalid",
      admin: true,
      encrypted_password: Bcrypt.hash_pwd_salt("access-password-1", log_rounds: 4),
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{scope: Scope.for_user(Accounts.get(10701), "en")}
  end

  defp update!(sql), do: Repo.query!(sql <> " WHERE id=10701")

  test "a current admin is admitted with a refreshed user", %{scope: scope} do
    update!("UPDATE users SET email='access-renamed@example.invalid'")

    assert {:ok, %Scope{user: user}} = Access.admit(scope, :admin, env: @self_hosted)
    assert user.email == "access-renamed@example.invalid"
  end

  test "demotion refuses admin mode but keeps background mode", %{scope: scope} do
    update!("UPDATE users SET admin=false")

    assert Access.admit(scope, :admin, env: @self_hosted) == {:error, :unauthorized}
    assert {:ok, _} = Access.admit(scope, :background, env: @self_hosted)
  end

  test "a deleted actor or a changed password is a stale session", %{scope: scope} do
    update!(
      "UPDATE users SET encrypted_password='#{Bcrypt.hash_pwd_salt("other-password-2", log_rounds: 4)}'"
    )

    assert Access.admit(scope, :admin, env: @self_hosted) == {:error, :stale_session}
    assert Access.admit(scope, :background, env: @self_hosted) == {:error, :stale_session}

    fresh = Scope.for_user(Accounts.get(10701), "en")
    update!("UPDATE users SET deleted_at=now()")
    assert Access.admit(fresh, :admin, env: @self_hosted) == {:error, :stale_session}
  end

  test "Cloud refuses admin mode and admits background only with a valid operator grant",
       %{scope: scope} do
    System.put_env("SIDEKIQ_USERNAME", "synthetic-operator")
    System.put_env("SIDEKIQ_PASSWORD", "synthetic-password")
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    on_exit(fn ->
      System.delete_env("SIDEKIQ_USERNAME")
      System.delete_env("SIDEKIQ_PASSWORD")
    end)

    grant = String.duplicate("g", 43)
    {:ok, "OK"} = OperatorGrant.store(scope.user, "synthetic-login", grant)

    assert Access.admit(scope, :admin, env: @cloud) == {:error, :cloud}
    assert Access.admit(scope, :background, env: @cloud) == {:error, :cloud}

    assert {:ok, _} =
             Access.admit(scope, :background,
               env: @cloud,
               operator: %{"operator_grant" => grant, "operator_login" => "synthetic-login"}
             )

    assert Access.admit(scope, :background,
             env: @cloud,
             operator: %{"operator_grant" => grant, "operator_login" => "other-login"}
           ) == {:error, :cloud}
  end

  test "unsupported user settings are refused in both modes", %{scope: scope} do
    update!(~s(UPDATE users SET settings='{"timezone":"Not/AZone"}'))

    assert Access.admit(scope, :admin, env: @self_hosted) == {:error, :unsupported}
    assert Access.admit(scope, :background, env: @self_hosted) == {:error, :unsupported}
  end

  test "an OIDC instance refuses writes but keeps reads", %{scope: scope} do
    assert {:ok, _} = Access.admit(scope, :admin, env: @oidc)
    assert Access.admit(scope, :admin, env: @oidc, write: true) == {:error, :oidc}
    assert Access.admit(scope, :background, env: @oidc, write: true) == {:error, :oidc}
    assert {:ok, _} = Access.admit(scope, :admin, env: @self_hosted, write: true)
  end

  test "a missing scope is a stale session" do
    assert Access.admit(nil, :admin, env: @self_hosted) == {:error, :stale_session}
  end
end
