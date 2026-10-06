defmodule Dawarich.Auth.AccountDestroyTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, AccountDestroy, DestroyToken}
  alias Dawarich.{RailsSecret, Redis, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)

    Repo.query!("CREATE TEMP TABLE deletion_enqueues (user_id bigint NOT NULL)", [], log: false)

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email, encrypted_password, status, created_at, updated_at)
        VALUES($1, '', 1, NOW(), NOW()) RETURNING id
        """,
        ["destroy-#{System.unique_integer([:positive])}@dawarich.test"],
        log: false
      ).rows

    context = %{
      self_hosted: false,
      env: %{},
      rails_secret: RailsSecret.fetch(),
      enqueue_destroy: &enqueue/1
    }

    {:ok, token} = DestroyToken.issue(id, context)
    {:ok, claims} = DestroyToken.verify(token, context)
    on_exit(fn -> Redis.cache_command(["DEL", "account_destroy:consumed:" <> claims["jti"]]) end)
    %{id: id, token: token, context: context}
  end

  @tag :f6_rollback
  test "transactional deletion enqueue rollback preserves the link for exactly one retry", c do
    failing =
      Map.put(c.context, :enqueue_destroy, fn id ->
        :ok = enqueue(id)
        Repo.rollback(:enqueue_failed)
      end)

    assert {:error, :enqueue_failed} = AccountDestroy.confirm(c.token, failing)
    assert_live_without_enqueue(c.id)
    assert_single_success(c)
  end

  @tag :f6_exception
  test "transactional deletion enqueue exception preserves the link for exactly one retry", c do
    failing =
      Map.put(c.context, :enqueue_destroy, fn id ->
        :ok = enqueue(id)
        raise "deletion enqueue failed"
      end)

    assert_raise RuntimeError, "deletion enqueue failed", fn ->
      AccountDestroy.confirm(c.token, failing)
    end

    assert_live_without_enqueue(c.id)
    assert_single_success(c)
  end

  @tag :f6_success
  test "committed deletion enqueue consumes the confirmation link exactly once", c do
    assert_single_success(c)
  end

  defp enqueue(id) do
    Repo.query!("INSERT INTO deletion_enqueues(user_id) VALUES($1)", [id], log: false)
    :ok
  end

  defp assert_live_without_enqueue(id) do
    assert Repo.get!(Account, id).deleted_at == nil
    assert Repo.query!("SELECT user_id FROM deletion_enqueues", [], log: false).rows == []
  end

  defp assert_single_success(c) do
    assert {:ok, :scheduled} = AccountDestroy.confirm(c.token, c.context)
    assert Repo.get!(Account, c.id).deleted_at != nil
    assert {:error, :replayed} = AccountDestroy.confirm(c.token, c.context)
    assert Repo.query!("SELECT user_id FROM deletion_enqueues", [], log: false).rows == [[c.id]]
  end
end
