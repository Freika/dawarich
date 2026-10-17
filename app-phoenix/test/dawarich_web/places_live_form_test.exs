defmodule DawarichWeb.PlacesLiveFormTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  alias Dawarich.Test.NativePlaces, as: N
  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Repo
  @endpoint DawarichWeb.Endpoint
  @attrs %{
    "name" => "Outside map",
    "latitude" => "51.12345678",
    "longitude" => "12.12345678",
    "note" => "Draft note",
    "tag_ids" => [""]
  }
  setup do: N.setup!()

  test "native create and edit persist notes tags coordinates and name locks", ctx do
    S.place!(ctx.actor.id, 118_501, "Before")
    S.tag!(ctx.actor.id, 118_511, "Tag", 118_501, ~N[2026-01-01 00:00:00])
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)

    render_submit(view, "save_place", %{
      "generation" => gen,
      "place" => %{@attrs | "tag_ids" => ["118511"]}
    })

    assert [[id, "Draft note", 51.123457, 12.123457, 0, lock]] =
             Repo.query!(
               "SELECT id,note,latitude::float8,longitude::float8,source,name_locked_at FROM places WHERE name='Outside map'",
               []
             ).rows

    assert lock != nil

    assert Repo.query!(
             "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
             [id]
           ).rows == [[118_511]]

    Repo.query!("UPDATE places SET source=1,demo=true WHERE id=$1", [id])
    render_click(view, "open_edit", %{"id" => to_string(id)})

    render_submit(view, "save_place", %{
      "generation" => N.generation(view, :form_state),
      "place" => %{"name" => "Edited", "note" => "Updated", "tag_ids" => [""]}
    })

    assert Repo.query!("SELECT name,note,source,demo,latitude::float8 FROM places WHERE id=$1", [
             id
           ]).rows == [["Edited", "Updated", 1, false, 51.123457]]

    assert Repo.query!(
             "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
             [id]
           ).rows == []
  end

  test "invalid Place submit keeps dialog values errors and retry without writes", ctx do
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)

    html =
      render_submit(view, "save_place", %{
        "generation" => gen,
        "place" => %{@attrs | "name" => "", "longitude" => "bad"}
      })

    assert html =~ "Draft note"
    assert has_element?(view, "dialog [role=alert]")
    assert Repo.query!("SELECT id FROM places WHERE user_id=$1", [ctx.actor.id]).rows == []
    assert N.generation(view, :form_state) == gen
    render_submit(view, "save_place", %{"generation" => gen, "place" => @attrs})

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]

    render_click(view, "open_create", %{})
    refute render(view) =~ "Draft note"
  end

  test "overflowing coordinate validation retains dialog errors and values without effects",
       ctx do
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)
    overflow = String.duplicate("9", 400)

    for field <- ["latitude", "longitude"] do
      attrs = Map.put(@attrs, field, overflow)
      render_change(view, "validate_place", %{"generation" => gen, "place" => attrs})
      state = :sys.get_state(view.pid).socket.assigns.form_state
      assert state.generation == gen
      assert state.status == :idle
      assert state.changeset.params[field] == overflow
      assert Keyword.has_key?(state.changeset.errors, String.to_existing_atom(field))
      assert has_element?(view, "dialog textarea", "Draft note")
      assert has_element?(view, "dialog input[name='place[#{field}]'][value='#{overflow}']")
      assert Repo.query!("SELECT id FROM places WHERE user_id=$1", [ctx.actor.id]).rows == []
    end

    render_submit(view, "save_place", %{"generation" => gen, "place" => @attrs})

    assert Repo.query!(
             "SELECT latitude::float8,longitude::float8 FROM places WHERE user_id=$1",
             [ctx.actor.id]
           ).rows == [[51.123457, 12.123457]]
  end

  test "queued Place create submits produce one accepted record per generation", ctx do
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)
    render_submit(view, "save_place", %{"generation" => gen, "place" => @attrs})
    render_submit(view, "save_place", %{"generation" => gen, "place" => @attrs})

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]

    render_click(view, "open_create", %{})
    newgen = N.generation(view, :form_state)
    assert newgen != gen
    render_submit(view, "save_place", %{"generation" => gen, "place" => @attrs})

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]
  end

  test "partial Place save reloads saved identity and refuses blind create retry", ctx do
    S.tag!(ctx.actor.id, 118_511, "Tag", 118_599, ~N[2026-01-01 00:00:00])
    previous = Application.get_env(:dawarich, :native_places_write_opts)

    Application.put_env(:dawarich, :native_places_write_opts,
      repo: Dawarich.Test.PlacesTagFailureRepo
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :native_places_write_opts, previous),
        else: Application.delete_env(:dawarich, :native_places_write_opts)
    end)

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)
    attrs = %{@attrs | "tag_ids" => ["118511"]}
    render_submit(view, "save_place", %{"generation" => gen, "place" => attrs})
    assert :sys.get_state(view.pid).socket.assigns.form_state.status == :partial
    assert has_element?(view, "[phx-click=recover_place]")
    render_submit(view, "save_place", %{"generation" => gen, "place" => attrs})

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]

    render_click(view, "recover_place", %{})
    assert N.generation(view, :form_state) != gen
    assert :sys.get_state(view.pid).socket.assigns.place_data.id != nil
  end

  test "uncertain create acknowledgement consumes generation and recovers through the list",
       ctx do
    previous = Application.get_env(:dawarich, :native_places_write_opts)

    Application.put_env(:dawarich, :native_places_write_opts,
      repo: Dawarich.Test.PlacesCommitAckFailureRepo
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :native_places_write_opts, previous),
        else: Application.delete_env(:dawarich, :native_places_write_opts)
    end)

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "open_create", %{})
    gen = N.generation(view, :form_state)
    params = %{"generation" => gen, "place" => @attrs}
    render_submit(view, "save_place", params)
    assert :sys.get_state(view.pid).socket.assigns.form_state.status == :uncertain

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]

    assert has_element?(view, "form[data-form-status=uncertain] button[type=submit][disabled]")
    assert has_element?(view, "[data-uncertain-save][role=alert]")
    assert has_element?(view, "[phx-click=check_places]")
    render_submit(view, "save_place", params)

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]

    render_click(view, "check_places", %{})
    assert :sys.get_state(view.pid).socket.assigns.form_state == nil
    assert has_element?(view, "#places table", "Outside map")
    render_submit(view, "save_place", params)

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]
  end

  test "reconnected draft reloads owned identity and validates without replaying submit", ctx do
    S.place!(ctx.actor.id, 118_501, "Owned")
    S.place!(ctx.other.id, 118_502, "Foreign")
    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    render_click(view, "recover_place_draft", %{"id" => "118501", "place" => @attrs})
    assert :sys.get_state(view.pid).socket.assigns.place_data.id == 118_501
    assert has_element?(view, "dialog textarea", "Draft note")
    assert Repo.query!("SELECT name FROM places WHERE id=118501", []).rows == [["Owned"]]
    render_click(view, "cancel_form", %{})
    render_click(view, "recover_place_draft", %{"id" => "118502", "place" => @attrs})
    assert :sys.get_state(view.pid).socket.assigns.form_state == nil
    render_click(view, "recover_place_draft", %{"id" => "", "place" => @attrs})
    assert has_element?(view, "dialog textarea", "Draft note")

    assert Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows == [
             [1]
           ]
  end
end
