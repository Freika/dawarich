defmodule DawarichWeb.PublicFamilyAdmissionTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo, SharedLinks}
  alias Dawarich.Sharing.Public
  alias Dawarich.Test.{FrameSeeds, TripsSeeds}
  @id "ac800000-0000-4000-8000-000000000001"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("consented_map_en"))
    saved = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if saved, do: System.put_env("SELF_HOSTED", saved), else: System.delete_env("SELF_HOSTED")
    end)

    TripsSeeds.shared_link!(%{id: @id, user_id: owner.id, resource_type: 3, trip_id: nil})

    [[family]] =
      Repo.query!("SELECT family_id FROM family_memberships WHERE user_id=$1", [owner.id],
        log: false
      ).rows

    Repo.query!(
      "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
      [@id, %{"audience" => "family", "family_id" => to_string(family)}],
      log: false
    )

    %{owner: owner, family: family, now: DateTime.utc_now()}
  end

  test "family public deadline follows authoritative inherited access and removal refuses", c do
    due = DateTime.add(c.now, 300)

    Repo.query!(
      "UPDATE families SET access_until=$2 WHERE id=$1",
      [c.family, DateTime.to_naive(due)],
      log: false
    )

    Repo.query!(
      "UPDATE users SET active_until=$2 WHERE id=$1",
      [c.owner.id, DateTime.to_naive(DateTime.add(c.now, -60))],
      log: false
    )

    {:ok, grant} =
      Public.grant(
        SharedLinks.active(@id, c.now),
        Accounts.get(90102),
        c.now,
        DateTime.add(c.now, 1800)
      )

    assert {:ok, page} = Public.read(grant, c.now)
    assert page.expires_at == DateTime.to_unix(due)
    Repo.query!("DELETE FROM family_memberships WHERE user_id=90102", [], log: false)
    assert {:error, _} = Public.read(grant, c.now)
  end
end
