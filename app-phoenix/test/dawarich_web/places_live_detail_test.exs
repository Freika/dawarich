defmodule DawarichWeb.PlacesLiveDetailTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  alias Dawarich.Test.NativePlaces, as: N
  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Repo
  @endpoint DawarichWeb.Endpoint
  setup do
    ctx = N.setup!()
    S.place!(ctx.actor.id, 118_501, "Detail")
    S.tag!(ctx.actor.id, 118_511, "Tag", 118_501, ~N[2026-01-01 00:00:00])
    ctx
  end

  test "native Place detail preserves active stats five visits ties source tags and local times",
       ctx do
    S.tag!(ctx.actor.id, 118_512, "Tied tag", 118_501, ~N[2026-01-01 00:00:00])

    for id <- 118_521..118_526,
        do:
          S.visit!(ctx.actor.id, id, %{
            place_id: 118_501,
            started_at: NaiveDateTime.add(~N[2026-01-01 08:00:00], (id - 118_521) * 86400),
            ended_at: NaiveDateTime.add(~N[2026-01-01 08:30:00], (id - 118_521) * 86400)
          })

    S.visit!(ctx.other.id, 118_527, %{
      place_id: 118_501,
      name: "Foreign cutoff",
      started_at: ~N[2026-01-02 08:00:00],
      ended_at: ~N[2026-01-02 08:30:00]
    })

    S.visit!(ctx.actor.id, 118_528, %{
      place_id: 118_501,
      status: 2,
      started_at: ~N[2026-02-01 08:00:00],
      ended_at: ~N[2026-02-01 08:30:00]
    })

    S.visit!(ctx.actor.id, 118_529, %{
      place_id: 118_501,
      deleted_at: ~N[2026-02-01 08:00:00],
      started_at: ~N[2026-02-02 08:00:00],
      ended_at: ~N[2026-02-02 08:30:00]
    })

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_detail", %{"id" => "118501"})
    assert has_element?(view, "dialog [data-visit-count]", "6")
    assert has_element?(view, "dialog [data-total-minutes='180']", "3.0")
    assert has_element?(view, "dialog", "Tag")
    assert has_element?(view, "dialog a[href='/places/118501']")
    detail = :sys.get_state(view.pid).socket.assigns.detail
    assert Enum.map(detail.visits, & &1.name) == Enum.map(118_526..118_522//-1, &"Visit #{&1}")
    assert hd(detail.visits).started == ~N[2026-01-06 09:00:00]
    assert detail.source == "manual"
    assert Enum.map(detail.tags, & &1.name) == ["Tag", "Tied tag"]
  end

  test "note-only save preserves name source coordinates and tag selection", ctx do
    Repo.query!("UPDATE places SET source=1 WHERE id=118501", [])

    before =
      Repo.query!(
        "SELECT name,source,latitude,longitude,name_locked_at FROM places WHERE id=118501",
        []
      ).rows

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_detail", %{"id" => "118501"})
    gen = N.generation(view, :note_state)

    render_submit(view, "save_place_note", %{
      "generation" => gen,
      "place" => %{"note" => "<b>Literal</b>\nSecond line", "name" => "Forged"}
    })

    assert Repo.query!("SELECT note FROM places WHERE id=118501", []).rows == [
             ["<b>Literal</b>\nSecond line"]
           ]

    assert Repo.query!(
             "SELECT name,source,latitude,longitude,name_locked_at FROM places WHERE id=118501",
             []
           ).rows == before

    assert Repo.query!(
             "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=118501",
             []
           ).rows == [[118_511]]

    assert has_element?(view, "dialog textarea", "<b>Literal</b>")
    refute has_element?(view, "dialog b", "Literal")
    newgen = N.generation(view, :note_state)
    assert newgen != gen

    render_submit(view, "save_place_note", %{
      "generation" => gen,
      "place" => %{"note" => "Duplicate"}
    })

    assert Repo.query!("SELECT note FROM places WHERE id=118501", []).rows == [
             ["<b>Literal</b>\nSecond line"]
           ]

    render_submit(view, "save_place_note", %{
      "generation" => newgen,
      "place" => %{"note" => "Explicit second save"}
    })

    assert Repo.query!("SELECT note FROM places WHERE id=118501", []).rows == [
             ["Explicit second save"]
           ]
  end

  test "URL patches close detail and refuse its queued note generation", ctx do
    Repo.query!("UPDATE places SET note='Original note' WHERE id=118501", [])
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_detail", %{"id" => "118501"})
    gen = N.generation(view, :note_state)
    assert has_element?(view, "dialog[id^=place-note]")
    render_patch(view, "/places?page=2&source=manual")
    refute has_element?(view, "dialog[id^=place-note]")
    assert :sys.get_state(view.pid).socket.assigns.detail == nil
    assert :sys.get_state(view.pid).socket.assigns.note_state == nil

    render_submit(view, "save_place_note", %{
      "generation" => gen,
      "place" => %{"note" => "Queued old note"}
    })

    assert Repo.query!("SELECT note FROM places WHERE id=118501", []).rows == [["Original note"]]
  end

  test "detail late save after target deletion or actor revocation exposes no record", ctx do
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_detail", %{"id" => "118501"})
    gen = N.generation(view, :note_state)
    Repo.query!("DELETE FROM places WHERE id=118501", [])
    render_submit(view, "save_place_note", %{"generation" => gen, "place" => %{"note" => "Late"}})
    refute has_element?(view, "dialog[id^=place-note]")
    assert :sys.get_state(view.pid).socket.assigns.detail == nil
    N.revoke(ctx.actor)
    render_click(view, "open_detail", %{"id" => "118501"})
    assert_redirect(view, "/users/sign_in")
  end
end
