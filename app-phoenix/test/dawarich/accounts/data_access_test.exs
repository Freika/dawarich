defmodule Dawarich.Accounts.DataAccessTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.{DataAccess, Scope}
  alias Dawarich.NativeM5.Dependencies
  alias Dawarich.Test.NativeAdminUI

  setup do
    %{target: user} = NativeAdminUI.setup!()
    %{scope: Scope.for_user(user, "de")}
  end

  test "ordinary data admission reloads identity without requiring admin", %{scope: scope} do
    principal = Dependencies.principal(scope)
    assert {:ok, fresh} = DataAccess.admit(principal)
    assert fresh.user.id == scope.user.id
    refute fresh.user.admin

    Repo.query!(
      "UPDATE users SET encrypted_password = $1 WHERE id = $2",
      ["new-identity-00000000000000000000", scope.user.id],
      log: false
    )

    assert {:error, :stale_session} = DataAccess.admit(principal)
    assert {:error, :stale_session} = DataAccess.admit(scope)
  end

  test "private principal contains no user credentials and inspection is redacted", %{
    scope: scope
  } do
    principal = Dependencies.principal(scope)
    refute inspect(principal) =~ scope.user.encrypted_password
    refute inspect(principal) =~ scope.user.api_key
    refute Map.has_key?(Map.from_struct(principal), :user)
    assert {:ok, _} = DataAccess.admit(principal)
    assert {:error, :stale_session} = DataAccess.admit(nil)
    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = $1", [scope.user.id], log: false)
    assert is_nil(Accounts.get(scope.user.id))
    assert {:error, :stale_session} = DataAccess.admit(principal)
  end
end
