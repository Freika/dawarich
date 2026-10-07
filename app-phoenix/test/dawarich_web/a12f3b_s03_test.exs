defmodule DawarichWeb.A12f3bS03Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.TrackMutations
  alias DawarichWeb.TrackShareActions

  setup do
    %{actor: S.seed!()}
  end

  @tag a12f3b_case: "S03a"
  test "track share new and create match Rails ownership and rollback", %{actor: actor} do
    assert {:ok, page} = S.read(actor, "track")
    assert page.trip.name =~ "2 km"
    form = S.request(actor, "track", :new) |> TrackShareActions.call(:new)
    assert form.status == 200
    head = S.request(actor, "track", :new) |> Map.put(:method, "HEAD")
    assert TrackShareActions.native?(head, head.path_params)
    assert (head |> Plug.Head.call([]) |> TrackShareActions.call(:new)).status == 200
    assert form.resp_body =~ "/tracks/99103/share_link"

    missing =
      S.request(actor, "track", :new, %{}, track_id: "99104") |> TrackShareActions.call(:new)

    assert missing.status == 404

    absent =
      S.request(actor, "track", :new, %{}, track_id: "99999999") |> TrackShareActions.call(:new)

    assert absent.status == 404

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
  test "track share validation cannot mutate an active grant", %{actor: actor} do
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
