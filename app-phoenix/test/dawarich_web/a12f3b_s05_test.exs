defmodule DawarichWeb.A12f3bS05Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.TrackMutations
  alias DawarichWeb.SharedLinkCookie
  import Plug.Test

  setup do
    %{actor: S.seed!()}
  end

  @tag a12f3b_case: "S05a"
  test "track URL regeneration preserves fields and invalidates old token", %{actor: actor} do
    assert {:ok, %{share: original}} =
             TrackMutations.run(actor, 99103, :create, S.params("track"), "en", now: S.now())

    assert {:ok, %{share: rotated, committed?: true}} =
             TrackMutations.run(actor, 99103, :regenerate, %{}, "en", now: S.now())

    refute rotated.id == original.id

    for key <- [:name, :magic_phrase, :settings, :resource_id, :user_id],
        do: assert(rotated[key] == original[key])

    assert NaiveDateTime.compare(rotated.expires_at, original.expires_at) == :eq
    refute Dawarich.SharedLinks.active(original.id, S.now())

    assert Repo.query!("SELECT id FROM shared_links WHERE id=$1::text::uuid", [original.id]).rows ==
             []

    Repo.query!("UPDATE shared_links SET expires_at=$1 WHERE id=$2::text::uuid", [
      ~N[2026-10-01 00:00:00],
      rotated.id
    ])

    assert {:missing, "/map/v2"} =
             TrackMutations.run(actor, 99103, :regenerate, %{}, "en", now: S.now())
  end

  @tag a12f3b_case: "S05b"
  test "track phrase regeneration invalidates old phrase cookie", %{actor: actor} do
    assert {:ok, %{share: original}} =
             TrackMutations.run(actor, 99103, :create, S.params("track"), "en", now: S.now())

    cookie = conn(:post, "/") |> SharedLinkCookie.put(original, DateTime.add(S.now(), 60))

    request =
      conn(:get, "/")
      |> put_req_cookie(
        "shared_link_#{original.id}",
        cookie.resp_cookies["shared_link_#{original.id}"].value
      )

    assert SharedLinkCookie.unlocked?(request, original, S.now())

    assert {:ok, %{share: rotated}} =
             TrackMutations.run(actor, 99103, :regenerate_phrase, %{}, "en",
               now: S.now(),
               phrase: fn -> "blue-fixture-hill" end
             )

    persisted = Dawarich.SharedLinks.active(rotated.id, S.now())
    assert persisted.magic_phrase == "blue-fixture-hill"
    assert persisted.resource_id == original.resource_id
    assert rotated.id == original.id
    refute SharedLinkCookie.unlocked?(request, persisted, S.now())
  end
end
