defmodule Dawarich.EntitlementsTest do
  use ExUnit.Case, async: true

  alias Dawarich.{Entitlements, Repo}
  alias Dawarich.Test.RailsUser

  @now ~U[2026-09-26 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp user(id, attrs),
    do:
      struct(
        Dawarich.Accounts.User,
        Map.merge(
          %{id: id},
          RailsUser.insert!(Map.merge(%{id: id, email: "a5s-ent-#{id}@dawarich.test"}, attrs))
        )
      )

  defp family(owner_id, member_id, access_until) do
    stamp = NaiveDateTime.utc_now(:second)

    {1, [%{id: id}]} =
      Repo.insert_all(
        "families",
        [
          %{
            name: "F",
            creator_id: owner_id,
            access_until: access_until,
            created_at: stamp,
            updated_at: stamp
          }
        ],
        returning: [:id]
      )

    Repo.insert_all("family_memberships", [
      %{family_id: id, user_id: member_id, role: 1, created_at: stamp, updated_at: stamp}
    ])
  end

  test "self-hosted and non-Lite plans have full access; a plain Lite user on Cloud does not" do
    lite = user(5401, %{plan: 0})
    assert Entitlements.full_access?(lite, true, @now)
    assert Entitlements.full_access?(user(5402, %{plan: 1}), false, @now)
    refute Entitlements.full_access?(lite, false, @now)
  end

  test "a Lite member inherits access from the family's access_until or a live Family-plan owner" do
    owner = user(5411, %{plan: 2, active_until: ~N[3026-01-01 00:00:00]})
    member = user(5412, %{plan: 0})
    family(owner.id, member.id, nil)
    assert Entitlements.full_access?(member, false, @now)

    lapsed = user(5413, %{plan: 2, active_until: ~N[2020-01-01 00:00:00]})
    member2 = user(5414, %{plan: 0})
    family(lapsed.id, member2.id, nil)
    refute Entitlements.full_access?(member2, false, @now)

    member3 = user(5415, %{plan: 0})
    family(lapsed.id, member3.id, ~N[3026-01-01 00:00:00])
    assert Entitlements.full_access?(member3, false, @now)

    pro_owner = user(5416, %{plan: 1, active_until: ~N[3026-01-01 00:00:00]})
    member4 = user(5417, %{plan: 0})
    family(pro_owner.id, member4.id, nil)
    refute Entitlements.full_access?(member4, false, @now)

    live_family_owner = user(5418, %{plan: 2, active_until: ~N[3026-01-01 00:00:00]})
    member5 = user(5419, %{plan: 0})
    family(live_family_owner.id, member5.id, ~N[2020-01-01 00:00:00])
    refute Entitlements.full_access?(member5, false, @now)
  end

  test "a soft-deleted owner passes nothing on" do
    owner =
      user(5421, %{
        plan: 2,
        active_until: ~N[3026-01-01 00:00:00],
        deleted_at: ~N[2026-01-01 00:00:00]
      })

    member = user(5422, %{plan: 0})
    family(owner.id, member.id, nil)
    refute Entitlements.full_access?(member, false, @now)
  end

  test "access/3 returns the expected {full?, plan} pair for self-hosted, Cloud pro, Cloud family, and Cloud lite with and without inherited access" do
    self_hosted = user(5441, %{plan: 0})
    assert Entitlements.access(self_hosted, true, @now) == {true, "lite"}

    pro = user(5442, %{plan: 1})
    assert Entitlements.access(pro, false, @now) == {true, "pro"}

    family_plan = user(5446, %{plan: 2})
    assert Entitlements.access(family_plan, false, @now) == {true, "family"}

    lite = user(5443, %{plan: 0})
    assert Entitlements.access(lite, false, @now) == {false, "lite"}

    owner = user(5444, %{plan: 2, active_until: ~N[3026-01-01 00:00:00]})
    member = user(5445, %{plan: 0})
    family(owner.id, member.id, nil)
    assert Entitlements.access(member, false, @now) == {true, "family"}
  end

  test "families?/3: self-hosted, the inherited family, or the user's own live Family plan; false when lapsed" do
    lite = user(5431, %{plan: 0})
    assert Entitlements.families?(lite, true, @now)
    refute Entitlements.families?(lite, false, @now)

    assert Entitlements.families?(
             user(5432, %{plan: 2, active_until: ~N[3026-01-01 00:00:00]}),
             false,
             @now
           )

    refute Entitlements.families?(
             user(5433, %{plan: 2, active_until: ~N[2020-01-01 00:00:00]}),
             false,
             @now
           )

    refute Entitlements.families?(
             user(5434, %{plan: 1, active_until: ~N[3026-01-01 00:00:00]}),
             false,
             @now
           )

    member = user(5435, %{plan: 0})
    family(user(5436, %{plan: 1}).id, member.id, ~N[3026-01-01 00:00:00])
    assert Entitlements.families?(member, false, @now)
  end
end
