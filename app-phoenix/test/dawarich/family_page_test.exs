defmodule Dawarich.FamilyPageTest do
  use ExUnit.Case, async: true

  alias Dawarich.{Accounts, FamilyPage, Repo}
  alias Dawarich.Test.FrameSeeds

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  defp read(user, action, opts \\ []),
    do: FamilyPage.read(user, action, Keyword.merge([now: @now, self_hosted: true], opts))

  test "family page reads only actor membership and orders members by email", ctx do
    assert {:ok, page} = read(ctx.owner, :show)
    assert page.state == :show
    assert page.family.id == 91001
    assert page.owner?
    assert Enum.map(page.members, & &1.id) == [90102, 90101]
    assert Enum.map(page.members, & &1.email) == [ctx.member.email, ctx.owner.email]
    assert Enum.map(page.members, & &1.membership_id) == [92002, 92001]
    assert page.me.id == ctx.owner.id
    assert page.pending_requests == %{90102 => 94001}
    assert page.family.created_date == ~D[2026-09-03]
    assert {:ok, member} = read(ctx.member, :show)
    refute member.owner?
    assert {:redirect, "/family/new", :not_in_family} = read(ctx.outsider, :show)
    assert {:redirect, "/", :not_authorized} = read(ctx.member, :edit)
    assert {:ok, %{state: :edit}} = read(ctx.owner, :edit)
  end

  test "new page avoids a lapsed family redirect loop", ctx do
    assert {:redirect, "/family", nil} = read(ctx.member, :new)

    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      DateTime.to_naive(@now)
    ])

    Repo.query!("UPDATE users SET plan = 1 WHERE id = $1", [ctx.owner.id])

    assert {:ok, %{state: :lapsed, owner?: false, members: [], me: me}} =
             read(ctx.member, :new, self_hosted: false)

    assert me.membership_id == 92002
    refute me.sharing.enabled?

    assert {:ok, %{state: :lapsed, owner?: true, members: members}} =
             read(Accounts.get(ctx.owner.id), :new, self_hosted: false)

    assert Enum.map(members, & &1.id) == [90102, 90101]

    assert {:redirect, "/family/new", :feature_unavailable} =
             read(ctx.member, :show, self_hosted: false)

    assert {:ok, %{state: :create}} = read(ctx.outsider, :new)
    assert {:ok, %{state: :upgrade}} = read(ctx.outsider, :new, self_hosted: false)
    assert {:ok, %{state: :create}} = read(%{ctx.outsider | plan: 2}, :new, self_hosted: false)
  end

  test "Cloud access honors access until before creator subscription and counts pending seats",
       ctx do
    assert {:ok, page} = read(ctx.member, :show, self_hosted: false)
    assert page.member_count == 2
    assert page.pending_count == 1
    assert page.can_invite?
    assert Enum.map(page.invitations, & &1.id) == [93001]

    Repo.query!(
      "UPDATE family_invitations SET expires_at = $1 WHERE id IN (93002, 93003)",
      [~N[2026-10-04 10:00:00]]
    )

    assert {:ok, full} = read(ctx.member, :show, self_hosted: false)
    assert full.pending_count == 3
    refute full.can_invite?
    assert {:ok, unlimited} = read(ctx.member, :show)
    assert unlimited.can_invite?

    for at <- [~N[2026-10-03 10:00:00], ~N[2026-10-03 09:59:59]] do
      Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [at])

      assert {:redirect, "/family/new", :feature_unavailable} =
               read(ctx.member, :show, self_hosted: false)

      assert {:ok, %{state: :show}} = read(ctx.owner, :show, self_hosted: false)
    end

    Repo.query!("UPDATE users SET plan = 1 WHERE id = $1", [ctx.owner.id])

    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      ~N[2026-10-04 10:00:00]
    ])

    assert {:ok, %{state: :show}} = read(ctx.member, :show, self_hosted: false)
    Repo.query!("UPDATE families SET access_until = NULL WHERE id = 91001", [])

    assert {:redirect, "/family/new", :feature_unavailable} =
             read(ctx.member, :show, self_hosted: false)
  end

  test "family request page authorizes the target and preserves expired display state", ctx do
    assert {:ok, %{state: :request, request: active, members: []}} =
             read(ctx.member, {:request, 94001})

    assert active.requester_email == ctx.owner.email
    assert active.status == 0
    assert active.display == :pending
    assert {:ok, %{request: expired}} = read(ctx.member, {:request, 94002})
    assert expired.status == 0
    assert expired.display == :expired
    assert {:redirect, "/family", :not_request_target} = read(ctx.owner, {:request, 94001})
    assert {:error, 404} = read(ctx.member, {:request, 999_999})
    assert {:redirect, "/", :not_in_family} = read(ctx.outsider, {:request, 94001})

    Repo.insert_all("families", [
      %{
        id: 91002,
        creator_id: ctx.outsider.id,
        name: "Foreign fixture",
        created_at: DateTime.to_naive(@now),
        updated_at: DateTime.to_naive(@now)
      }
    ])

    Repo.query!("UPDATE family_location_requests SET family_id = 91002 WHERE id = 94002", [])
    assert {:error, 404} = read(ctx.member, {:request, 94002})
  end

  test "lapsed invitation index remains readable without location data", ctx do
    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      DateTime.to_naive(@now)
    ])

    Repo.query!("UPDATE users SET plan = 1 WHERE id = $1", [ctx.owner.id])

    for user <- [Accounts.get(ctx.owner.id), ctx.member] do
      assert {:ok, %{state: :invitations, members: [], invitations: invitations}} =
               read(user, :invitations, self_hosted: false)

      assert Enum.map(invitations, & &1.id) == [93001]
    end

    assert {:redirect, "/family/new", :not_in_family} =
             read(ctx.outsider, :invitations, self_hosted: false)

    assert Repo.query!("SELECT status FROM family_invitations WHERE id = 93002").rows == [[0]]
  end

  test "family page contains no coordinates point rows or API credentials", ctx do
    fixture = FrameSeeds.load_family("consented_map_en")
    for row <- fixture["rows"]["points"], do: Dawarich.Test.ApiGolden.insert!("points", row)

    for actor <- fixture["actors"] do
      Repo.query!("UPDATE users SET settings = $2 WHERE id = $1", [actor["id"], actor["settings"]])
    end

    assert {:ok, page} = read(Accounts.get(ctx.owner.id), :show)
    member = Enum.find(page.members, &(&1.id == ctx.member.id))
    assert member.sharing.enabled?
    assert member.latest_timestamp == 1_791_021_300
    encoded = Jason.encode!(page)

    for forbidden <-
          ~w(api_key lonlat latitude longitude coordinates points raw_data settings encrypted_password),
        do: refute(String.contains?(encoded, forbidden))

    refute String.contains?(encoded, "a9fpl-fixture-")
    assert :rails = read(%{ctx.owner | settings: []}, :show)
    assert :rails = read(%{ctx.owner | settings: %{"timezone" => []}}, :show)

    assert :rails =
             read(
               %{
                 ctx.owner
                 | settings: %{"family" => %{"location_sharing" => %{"duration" => []}}}
               },
               :show
             )

    Repo.query!("UPDATE users SET settings = $2 WHERE id = $1", [ctx.member.id, %{"family" => []}])

    assert :rails = read(ctx.owner, :show)
  end
end
