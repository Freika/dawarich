defmodule Dawarich.PlacesTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Places, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds, as: S

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    actor = S.user!(11801)
    other = S.user!(11802)
    %{actor: actor, other: other, scope: Scope.for_user(actor, "en")}
  end

  test "scoped Places reads preserve page casts coordinates and local dates", ctx do
    for id <- 118_023..118_001//-1, do: S.place!(ctx.actor.id, id, "Place #{id}")
    S.place!(ctx.other.id, 118_000, "Foreign")
    S.place!(ctx.actor.id, 118_024, "Legacy", legacy: true)
    Repo.query!("UPDATE places SET created_at=$1 WHERE id=$2", [~N[2026-01-05 09:30:00], 118_001])
    assert {:ok, first} = apply(Places, :list, [ctx.scope, nil])
    assert Enum.map(first.entries, & &1.id) == Enum.to_list(118_001..118_020)
    assert first.total_pages == 2
    assert hd(first.entries).created.local == ~N[2026-01-05 10:30:00.000000]
    assert {:ok, second} = apply(Places, :list, [ctx.scope, "2x"])
    assert Enum.map(second.entries, & &1.id) == Enum.to_list(118_021..118_024)
    assert List.last(second.entries).lat == 51.3397
    assert {:ok, %{entries: [], total_pages: 0}} = apply(Places, :list, [ctx.scope, "99"])
    assert apply(Places, :list, [ctx.scope, "0"]) == {:ok, first}
    refute inspect(first) =~ "api_key"
  end

  test "native Places edges have typed outcomes without handback", ctx do
    S.place!(ctx.actor.id, 118_001, "Own")
    S.place!(ctx.other.id, 118_002, "Foreign")

    for page <- [[], %{}, "1000000000000001"],
        do: assert(apply(Places, :list, [ctx.scope, page]) == {:error, :invalid_input})

    for id <- [nil, "no", "0", %{}, "99999999999999999999", "118002", "118099"],
        do: assert(apply(Places, :detail, [ctx.scope, id]) == {:error, :not_found})

    Repo.query!("UPDATE places SET source=7 WHERE id=118001", [])
    assert apply(Places, :detail, [ctx.scope, "118001"]) == {:error, :unsupported}
    assert apply(Places, :edit, [ctx.scope, "118001"]) == {:error, :unsupported}

    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [
      %{"timezone" => "Mars/Phobos"},
      ctx.actor.id
    ])

    assert apply(Places, :list, [ctx.scope, nil]) == {:error, :unsupported}
    assert apply(Places, :list, [ctx.scope, "99"]) == {:ok, %{entries: [], total_pages: 0}}

    assert apply(Places, :list, [ctx.scope, nil, [repo: Dawarich.Test.PlacesUnavailableRepo]]) ==
             {:error, :unavailable}
  end

  test "native Place detail never exposes foreign dependent data", ctx do
    S.place!(ctx.actor.id, 118_001, "Own")
    S.tag!(ctx.actor.id, 118_101, "Owned tag", 118_001, ~N[2026-01-01 00:00:00])
    S.tag!(ctx.other.id, 118_102, "Foreign tag", 118_001, ~N[2026-01-01 00:00:00])

    for id <- 118_201..118_206 do
      S.visit!(ctx.actor.id, id, %{
        place_id: 118_001,
        started_at: NaiveDateTime.add(~N[2026-01-01 08:00:00], (id - 118_201) * 86400),
        ended_at: NaiveDateTime.add(~N[2026-01-01 08:30:00], (id - 118_201) * 86400)
      })
    end

    S.visit!(ctx.other.id, 118_207, %{
      place_id: 118_001,
      name: "Foreign visit",
      started_at: ~N[2026-01-02 08:00:00],
      ended_at: ~N[2026-01-02 08:30:00]
    })

    S.visit!(ctx.actor.id, 118_208, %{
      place_id: 118_001,
      started_at: ~N[2026-01-08 08:00:00],
      ended_at: ~N[2026-01-08 08:30:00],
      status: 2
    })

    S.visit!(ctx.actor.id, 118_209, %{
      place_id: 118_001,
      started_at: ~N[2026-01-09 08:00:00],
      ended_at: ~N[2026-01-09 08:30:00],
      deleted_at: ~N[2026-02-01 08:00:00]
    })

    assert {:ok, detail} = apply(Places, :detail, [ctx.scope, "118001"])
    assert detail.visit_count == 6
    assert detail.total_minutes == 180
    assert Enum.map(detail.visits, & &1.name) == Enum.map(118_206..118_202//-1, &"Visit #{&1}")
    assert hd(detail.visits).started == ~N[2026-01-06 09:00:00]
    assert Enum.map(detail.tags, & &1.name) == ["Owned tag"]
    refute inspect(detail) =~ "Foreign"
    assert {:ok, edit} = apply(Places, :edit, [ctx.scope, "118001"])
    assert edit.tag_ids == [118_101]
    assert Enum.map(edit.tags, & &1.id) == [118_101]
    assert {edit.latitude, edit.longitude, edit.source} == {51.3397, 12.3731, "manual"}
    refute inspect(edit) =~ "Foreign"
    Repo.query!("UPDATE places SET lonlat=NULL WHERE id=118001", [])
    assert apply(Places, :edit, [ctx.scope, "118001"]) == {:error, :unsupported}
  end

  test "Places admission refuses deleted and changed-password identities before projection",
       ctx do
    S.place!(ctx.actor.id, 118_001, "Own")

    Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("z", 60),
      ctx.actor.id
    ])

    assert apply(Places, :list, [ctx.scope, nil]) == {:error, :stale_session}
    fresh = Scope.for_user(Accounts.get(ctx.actor.id), "en")
    assert {:ok, %{entries: [_]}} = apply(Places, :list, [fresh, nil])
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [ctx.actor.id])
    assert apply(Places, :detail, [fresh, "118001"]) == {:error, :stale_session}
    assert apply(Places, :edit, [fresh, "118001"]) == {:error, :stale_session}
  end
end
