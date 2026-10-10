defmodule DawarichWeb.A12f3bS03Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.TrackMutations
  alias Dawarich.Sharing

  setup do
    %{actor: S.seed!()}
  end

  @tag a12f3b_case: "S03a"
  test "native S03a track reads and create preserve Rails ownership and rollback", %{actor: actor} do
    assert {:ok, page} = S.read(actor, "track")
    assert page.trip.name =~ "2 km"
    scope = Dawarich.Accounts.Scope.for_user(actor, "en")

    assert {:ok, %{trip: %{name: name}}} =
             Sharing.page(scope, %{type: :track, owner_id: actor.id, id: 99103}, %{},
               now: S.now()
             )

    assert name =~ "2 km"

    for id <- [99104, 99_999_999] do
      assert {:error, :not_found} =
               Sharing.page(scope, %{type: :track, owner_id: actor.id, id: id}, %{}, now: S.now())
    end

    assert {:ok, %{share: share, committed?: true}} =
             TrackMutations.run(actor, 99103, :create, S.params("track", %{"name" => ""}), "en",
               now: S.now()
             )

    assert share.name == page.trip.name
    assert share.resource_type == 1
    assert share.resource_id == 99103
    assert share.settings["show_photos"]
    refute Dawarich.SharedLinks.active(S.id(7), S.now())
    before = S.rows()

    Repo.query!(
      "ALTER TABLE shared_links ADD CONSTRAINT a12f3b_track_sql CHECK(name <> 'Rejected SQL') NOT VALID"
    )

    assert_raise Postgrex.Error, fn ->
      TrackMutations.run(
        actor,
        99103,
        :create,
        S.params("track", %{"name" => "Rejected SQL"}),
        "en",
        now: S.now()
      )
    end

    assert S.rows() == before
    Repo.query!("ALTER TABLE shared_links DROP CONSTRAINT a12f3b_track_sql")
    Repo.query!("UPDATE tracks SET dominant_mode=NULL WHERE id=99103")
    miles = %{actor | settings: Map.put(actor.settings, "maps", %{"distance_unit" => "mi"})}
    assert {:ok, %{trip: %{name: label}}} = S.read(miles, "track")
    assert label == "Track · 3 Oct 2026 · 1 mi"
  end

  @tag a12f3b_case: "S03b"
  test "native S03b track validation cannot mutate an active grant", %{actor: actor} do
    before = S.rows()

    assert {:invalid, %{errors: [{:magic_phrase, _}]}} =
             TrackMutations.run(
               actor,
               99103,
               :create,
               S.params("track", %{"magic_phrase" => String.duplicate("x", 256)}),
               "en",
               now: S.now()
             )

    assert S.rows() == before
    assert Dawarich.SharedLinks.active(S.id(7), S.now())
  end
end
