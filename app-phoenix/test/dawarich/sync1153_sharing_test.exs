defmodule Dawarich.Sync1153SharingTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.SharedLinks.FamilyAudience

  test "family shares follow current membership and retain the recorded family" do
    owner = user!()
    member = user!()
    stranger = user!()

    [[family]] =
      Repo.query!(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Synthetic family',$1,now(),now()) RETURNING id",
        [owner]
      ).rows

    for id <- [owner, member],
        do:
          Repo.query!(
            "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
            [family, id]
          )

    link = %{user_id: owner, settings: %{"audience" => "family", "family_id" => family}}
    now = DateTime.utc_now()
    assert FamilyAudience.accessible?(link, %{id: member}, now, true)
    refute FamilyAudience.accessible?(link, nil, now, true)
    refute FamilyAudience.accessible?(link, %{id: stranger}, now, true)

    refute FamilyAudience.accessible?(
             put_in(link.settings["family_id"], family + 1),
             %{id: member},
             now,
             true
           )

    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [owner])
    refute FamilyAudience.accessible?(link, %{id: member}, now, true)
  end
end
