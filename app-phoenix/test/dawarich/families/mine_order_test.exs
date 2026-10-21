defmodule Dawarich.Families.MineOrderTest do
  use Dawarich.IngestCase, async: true
  alias Dawarich.Families.Mine
  alias Dawarich.Test.FrameSeeds

  test "mine retains captured member order after physical row updates" do
    owner =
      FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en")) |> Map.put(:timezone, "UTC")

    Repo.query!("UPDATE users SET settings=settings WHERE id=$1", [owner.id])
    Repo.query!("UPDATE family_memberships SET role=role WHERE user_id=$1", [owner.id])

    for setting <- ~w(enable_indexscan enable_bitmapscan enable_hashjoin enable_mergejoin),
        do: Repo.query!("SET LOCAL #{setting}=off")

    assert {:ok, 200, {:object, payload}} = Mine.read(owner, ~U[2026-10-03 10:00:00Z])
    members = Enum.find_value(payload, fn {key, value} -> if key == "members", do: value end)

    ids =
      Enum.map(members, fn {:object, fields} ->
        Enum.find_value(fields, fn {key, value} -> if key == "user_id", do: value end)
      end)

    assert ids == [90101, 90102]
  end
end
