defmodule DawarichWeb.A12f3bF01Test do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{Accounts, FamilyPage, Repo}
  alias Dawarich.Test.FrameSeeds
  alias DawarichWeb.NativeFamilyAuth

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  @tag a12f3b_case: "F01a"
  test "native F01a family pages resolve lapsed and malformed actor states before effects", ctx do
    assert {:redirect, "/family/new", :not_in_family} =
             FamilyPage.read(ctx.outsider, :show, now: @now, self_hosted: true)

    assert {:ok, %{owner?: false}} =
             FamilyPage.read(ctx.member, :show, now: @now, self_hosted: true)

    assert {:redirect, "/", :not_authorized} =
             FamilyPage.read(ctx.member, :edit, now: @now, self_hosted: true)

    Repo.query!("UPDATE families SET access_until=$1 WHERE id=91001", [DateTime.to_naive(@now)])
    Repo.query!("UPDATE users SET plan=1 WHERE id=$1", [ctx.owner.id])

    assert {:redirect, "/family/new", :feature_unavailable} =
             FamilyPage.read(Accounts.get(ctx.owner.id), :show, now: @now, self_hosted: false)

    assert {:ok, %{state: :lapsed}} =
             FamilyPage.read(ctx.member, :new, now: @now, self_hosted: false)

    Repo.query!(~s(UPDATE users SET settings='{"timezone":[]}'::jsonb WHERE id=$1), [ctx.owner.id])

    assert {:error, :invalid_input} =
             Dawarich.Families.page(Dawarich.Accounts.Scope.for_user(ctx.owner, "en"), :show,
               now: @now,
               self_hosted: true
             )

    assert {:halt, cleared} = NativeFamilyAuth.authorize(socket(ctx.owner, nil))
    assert cleared.assigns.page == nil
    assert cleared.redirected == {:redirect, %{to: "/family/new", status: 302}}

    assert Repo.query!("SELECT count(*) FROM family_memberships WHERE family_id=91001").rows == [
             [2]
           ]
  end

  @tag a12f3b_case: "F01b"
  test "native F01b family reconnect cannot retain a removed membership", ctx do
    {:ok, page} = FamilyPage.read(ctx.member, :show, now: @now, self_hosted: true)

    socket = socket(ctx.member, page)

    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [ctx.member.id])
    assert {:halt, refreshed} = NativeFamilyAuth.authorize(socket)
    assert refreshed.redirected == {:redirect, %{to: "/family/new", status: 302}}
    assert refreshed.assigns.page == nil
  end

  defp socket(user, page) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_user: user,
        current_scope: Dawarich.Accounts.Scope.for_user(user, "en"),
        locale: "en",
        page: page,
        now: @now,
        self_hosted: true,
        request_path: "/family"
      }
    }
  end
end
