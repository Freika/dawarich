defmodule Dawarich.FamiliesScopeTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, Families, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds

  @now ~U[2026-10-03 10:00:00Z]
  @opts [now: @now, self_hosted: true]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("consented_map_en"))

    %{
      owner: Scope.for_user(owner, "en"),
      member: Scope.for_user(Accounts.get(90102), "en"),
      outsider: Scope.for_user(Accounts.get(90103), "en")
    }
  end

  test "family snapshots refuse removed lapsed and non-target viewers", ctx do
    assert {:ok, page} = Families.page(ctx.member, :show, @opts)
    assert page.family.id == 91001
    assert {:error, :unauthorized} = Families.page(ctx.owner, {:request, 94001}, @opts)
    assert {:error, :unauthorized} = Families.locations(ctx.outsider, @opts)
    Repo.query!("UPDATE families SET access_until=$1 WHERE id=91001", [DateTime.to_naive(@now)])
    Repo.query!("UPDATE users SET plan=1 WHERE id=90101")
    assert {:error, :expired} = Families.locations(ctx.member, self_hosted: false, now: @now)

    assert {:ok, %{state: :lapsed}} =
             Families.page(ctx.member, :new, self_hosted: false, now: @now)

    Repo.query!("DELETE FROM family_memberships WHERE user_id=90102")
    assert {:error, :unauthorized} = Families.page(ctx.member, :show, @opts)
  end

  test "consent expiring exactly now removes location and history", ctx do
    assert {:ok, locations} = Families.locations(ctx.owner, @opts)
    assert Enum.map(locations.locations, & &1["user_id"]) == [90102]
    params = %{"start_at" => "2026-10-01T00:00:00Z", "end_at" => "2026-10-03T10:00:00Z"}

    config = %{
      "enabled" => true,
      "share_history" => true,
      "history_before_sharing" => true,
      "history_window" => "all",
      "expires_at" => DateTime.to_iso8601(DateTime.add(@now, 1))
    }

    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [
      %{"family" => %{"location_sharing" => config}}
    ])

    assert {:ok, %{"members" => [_]}} = Families.history(ctx.owner, params, @opts)
    config = Map.put(config, "expires_at", DateTime.to_iso8601(@now))

    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [
      %{"family" => %{"location_sharing" => config}}
    ])

    assert {:ok, %{locations: []}} = Families.locations(ctx.owner, @opts)
    assert {:ok, %{"members" => []}} = Families.history(ctx.owner, params, @opts)
  end

  test "scoped family reads reject changed passwords locked and deleted actors", ctx do
    Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=90101", [
      String.duplicate("x", 60)
    ])

    assert {:error, :stale_session} = Families.page(ctx.owner, :show, @opts)
    Repo.query!("UPDATE users SET locked_at=$1 WHERE id=90102", [DateTime.utc_now()])
    assert {:error, :stale_session} = Families.locations(ctx.member, @opts)
    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=90103", [DateTime.utc_now()])
    assert {:error, :stale_session} = Families.page(ctx.outsider, :new, @opts)
  end

  test "native family snapshots omit invitation capabilities and unsupported input", ctx do
    assert {:ok, page} = Families.page(ctx.owner, :show, @opts)
    assert page.invitations != []
    assert Enum.all?(page.invitations, &(not Map.has_key?(&1, :token)))

    for field <- ~w(api_key encrypted_password token settings latitude longitude) do
      refute Jason.encode!(page) =~ field
    end

    assert {:error, :invalid_input} = Families.page(ctx.owner, :forged, @opts)
    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [%{"family" => []}])
    assert {:error, :invalid_input} = Families.page(ctx.owner, :show, @opts)
  end

  test "sanitized family principals admit fresh scopes and refuse changed session versions",
       ctx do
    principal = Dawarich.Accounts.Principal.project(ctx.owner.user)
    scope = Scope.for_user(principal, "en")
    refute Map.has_key?(principal, :encrypted_password)
    refute Map.has_key?(principal, :api_key)
    assert {:ok, %{family: %{id: 91001}}} = Families.page(scope, :show, @opts)

    Repo.query!(
      "UPDATE users SET encrypted_password=$1 WHERE id=90101",
      [String.duplicate("x", 60)],
      log: false
    )

    assert {:error, :stale_session} = Families.locations(scope, @opts)
  end

  test "family subscriptions authorize membership and carry only invalidation identity", ctx do
    assert :ok = Families.subscribe(ctx.owner, @opts)
    assert {:error, :unauthorized} = Families.subscribe(ctx.outsider, @opts)
    assert :ok = Dawarich.Families.Events.broadcast(ctx.owner.user.id, :membership)
    assert_receive {:domain_changed, 90101, :membership}
  end
end
