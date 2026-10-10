defmodule DawarichWeb.A12f3bN01Test do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Notifications}
  alias Dawarich.Test.RailsUser
  alias Dawarich.Accounts.Scope

  setup do
    actor = RailsUser.insert!(%{id: 73101, email: "n01@test"})
    other = RailsUser.insert!(%{id: 73102, email: "n01-other@test"})
    own = Notifications.create!(Repo, actor.id, :info, "Own", "Body")
    foreign = Notifications.create!(Repo, other.id, :info, "Foreign", "Body")
    %{actor: actor, other: other, own: own, foreign: foreign}
  end

  @tag a12f3b_case: "N01a"
  test "scoped notification actions preserve owner and forged target refusal", ctx do
    scope = Scope.for_user(Accounts.get(ctx.actor.id), "en")
    assert {:ok, _} = Notifications.mark_all_read(scope)
    assert Notifications.get(ctx.actor.id, ctx.own).read_at
    refute Notifications.get(ctx.other.id, ctx.foreign).read_at
    assert {:error, :not_found} = Notifications.delete(scope, ctx.foreign)
    assert Notifications.get(ctx.actor.id, ctx.own)
    assert {:ok, _} = Notifications.delete_all(scope)
    assert Notifications.get(ctx.actor.id, ctx.own) == nil
    assert Notifications.get(ctx.other.id, ctx.foreign)
    Repo.query!("UPDATE users SET encrypted_password='rotated' WHERE id=$1", [ctx.actor.id])
    assert {:error, :stale_session} = Notifications.delete_all(scope)
  end

  @tag a12f3b_case: "N01b"
  test "notification read validation failure preserves unread row", ctx do
    Repo.query!("UPDATE notifications SET title='', content='' WHERE id=$1", [ctx.own])
    notification = Notifications.get(ctx.actor.id, ctx.own)

    assert_raise Dawarich.Notifications.Invalid, fn ->
      Notifications.mark_read(ctx.actor.id, notification)
    end

    refute Notifications.get(ctx.actor.id, ctx.own).read_at
  end
end
