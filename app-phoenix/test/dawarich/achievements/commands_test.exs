defmodule Dawarich.Achievements.CommandsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

  test "scoped unlock commands retain lease token foreign-owner and once-seen rules" do
    RailsUser.insert!(%{id: 18802, email: "achievement-commands@example.invalid"})
    RailsUser.insert!(%{id: 18803, email: "achievement-foreign@example.invalid"})
    scope = Scope.for_user(Accounts.get(18802), "en")
    foreign = Scope.for_user(Accounts.get(18803), "en")

    [[id]] =
      rows(
        "INSERT INTO achievement_unlock_events(user_id,kind,key,created_at,updated_at) VALUES($1,'region','DE',now(),now()) RETURNING id",
        [scope.user.id]
      )

    now = [now: ~U[2026-07-20 10:00:00Z]]
    assert {:ok, claim} = command(:claim, [scope, %{}, now])
    assert claim.event.id == id
    assert {:ok, :busy} = command(:claim, [scope, %{}, now])
    assert {:ok, false} = command(:seen, [foreign, id, claim.event.claim_token, now])
    assert {:ok, false} = command(:seen, [scope, id, "wrong", now])
    assert {:ok, true} = command(:seen, [scope, id, claim.event.claim_token, now])
    assert {:ok, true} = command(:seen, [scope, id, claim.event.claim_token, now])
    assert {:ok, nil} = command(:claim, [scope, %{}, now])
    assert {:ok, :ok} = command(:dismiss, [scope, id, now])
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [scope.user.id], log: false)
    assert {:error, :stale_session} = command(:claim, [scope, %{}, now])
  end

  defp command(name, args), do: apply(Dawarich.Achievements.Commands, name, args)
end
