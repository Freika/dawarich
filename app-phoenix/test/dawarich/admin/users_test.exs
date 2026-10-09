defmodule Dawarich.Admin.UsersTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Users
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
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
end
