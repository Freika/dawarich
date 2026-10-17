defmodule Dawarich.Places.AccessTest do
  use ExUnit.Case, async: true
  alias Dawarich.{Places.Access, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds, as: S

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{scope: Scope.for_user(S.user!(11811), "en")}
  end

  test "Places admission allows ordinary Cloud actors and defers unsupported zone to reads",
       ctx do
    assert {:ok, scope} = apply(Access, :admit, [ctx.scope])
    assert scope.user.admin == false

    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [
      %{"timezone" => "Mars/Phobos"},
      scope.user.id
    ])

    assert {:ok, refreshed} = apply(Access, :admit, [ctx.scope])
    assert refreshed.user.settings["timezone"] == "Mars/Phobos"
    assert apply(Access, :admit, [nil]) == {:error, :stale_session}
    Repo.query!("UPDATE users SET locked_at=now() WHERE id=$1", [scope.user.id])
    assert apply(Access, :admit, [ctx.scope]) == {:error, :stale_session}
  end
end
