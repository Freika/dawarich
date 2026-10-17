defmodule Dawarich.Accounts.DataAccessTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.{DataAccess, Scope}
  alias Dawarich.Accounts.Principal
  alias Dawarich.Test.NativeAdminUI

  setup do
    %{target: user} = NativeAdminUI.setup!()
    %{scope: Scope.for_user(user, "de")}
  end

  test "M4 identity proofs admit data and Places without retaining account credentials", %{
    scope: scope
  } do
    proof = Principal.scope(scope)
    assert %Scope{user: %Dawarich.Accounts.Principal{session_version: version}} = proof
    assert version == Dawarich.Accounts.Principal.version(scope.user)

    assert Map.from_struct(proof.user)
           |> Map.drop([:id, :session_version, :settings])
           |> Map.values()
           |> Enum.all?(&is_nil/1)

    assert {:ok, fresh} = DataAccess.admit(proof)
    assert {:ok, place} = Dawarich.Places.Access.admit(proof)
    assert fresh.user.id == place.user.id

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-native-proof' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} = DataAccess.admit(proof)
    assert {:error, :stale_session} = Dawarich.Places.Access.admit(proof)
  end

  test "ordinary data admission reloads identity without requiring admin", %{scope: scope} do
    principal = Principal.scope(scope)
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
    principal = Principal.scope(scope)
    refute inspect(principal) =~ scope.user.encrypted_password
    refute inspect(principal) =~ scope.user.api_key
    assert %Scope{user: %Principal{}} = principal
    assert {:ok, _} = DataAccess.admit(principal)
    assert {:error, :stale_session} = DataAccess.admit(nil)
    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = $1", [scope.user.id], log: false)
    assert is_nil(Accounts.get(scope.user.id))
    assert {:error, :stale_session} = DataAccess.admit(principal)
  end
end
