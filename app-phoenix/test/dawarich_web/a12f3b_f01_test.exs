defmodule DawarichWeb.A12f3bF01Test do
  use Dawarich.JobsCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, FamilyPage, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.FamilyGate

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  @tag a12f3b_case: "F01a"
  test "family pages resolve lapsed and malformed actor states before effects", ctx do
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

    Repo.query!("UPDATE users SET settings='[]'::jsonb WHERE id=$1", [ctx.owner.id])

    conn =
      RailsUser.signed_in(ctx.owner.id)
      |> Map.put(:request_path, "/family")
      |> assign(:current_user, ctx.owner)
      |> assign(:now, @now)
      |> assign(:self_hosted, true)
      |> assign(:locale, "en")
      |> FamilyGate.call([])

    assert conn.status == 500
    refute Map.has_key?(conn.private, :dawarich_proxy)

    assert Repo.query!("SELECT count(*) FROM family_memberships WHERE family_id=91001").rows == [
             [2]
           ]
  end

  @tag a12f3b_case: "F01b"
  test "family reconnect cannot retain a removed membership", ctx do
    {:ok, page} = FamilyPage.read(ctx.member, :show, now: @now, self_hosted: true)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_user: ctx.member,
        page: page,
        now: @now,
        self_hosted: true,
        request_path: "/family"
      }
    }

    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [ctx.member.id])
    assert {:halt, refreshed} = FamilyGate.refresh("rails_flash", %{}, socket)
    assert refreshed.redirected == {:redirect, %{to: "/family/new", status: 302}}
    assert refreshed.assigns.page == nil
  end
end
