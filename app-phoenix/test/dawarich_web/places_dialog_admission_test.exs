defmodule DawarichWeb.PlacesDialogAdmissionTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{NativePlaces, FrameSeeds, SettingsReadProbe}
  alias DawarichWeb.PlacesLive.Form
  @endpoint DawarichWeb.Endpoint

  setup do
    ctx = NativePlaces.setup!()
    FrameSeeds.place!(ctx.actor.id, 118_701, "Owned dialog")
    ctx
  end

  for event <- ~w(open_create open_edit open_detail request_delete) do
    test "#{event} clears dialogs when settings change between projection and changeset admission",
         ctx do
      event = unquote(event)

      for value <- [[], 42] do
        Repo.query!(
          "UPDATE users SET settings=$2 WHERE id=$1",
          [ctx.actor.id, ctx.actor.settings],
          log: false
        )

        {:ok, view, _} = live(NativePlaces.conn(ctx.actor), "/places")
        render_click(view, "open_edit", %{"id" => "118701"})
        oldgen = NativePlaces.generation(view, :form_state)
        before = place_snapshot(ctx.actor)

        fragment =
          if event == "request_delete",
            do: "SELECT p.id, p.name",
            else: "SELECT id,name,icon,color FROM tags"

        {_, ref} =
          SettingsReadProbe.run(
            view.pid,
            fragment,
            fn ->
              Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [ctx.actor.id, value],
                log: false
              )
            end,
            fn -> render_click(view, event, %{"id" => "118701"}) end
          )

        assert_receive {:settings_read_probe, ^ref}
        assert_cleared(view)
        assert has_element?(view, "#native-places [role=alert]")
        refute has_element?(view, "#native-places dialog form")
        assert Accounts.settings(ctx.actor.id) == value
        assert place_snapshot(ctx.actor) == before

        render_submit(view, "save_place", %{
          "generation" => oldgen,
          "place" => %{"note" => "Stale queued note"}
        })

        assert place_snapshot(ctx.actor) == before
        GenServer.stop(view.pid)
      end
    end
  end

  test "dialog changeset admission refuses an actor revoked after the initial projection", ctx do
    {:ok, view, _} = live(NativePlaces.conn(ctx.actor), "/places")
    render_click(view, "open_edit", %{"id" => "118701"})
    before = place_snapshot(ctx.actor)

    {_, ref} =
      SettingsReadProbe.run(
        view.pid,
        "SELECT id,name,icon,color FROM tags",
        fn -> NativePlaces.revoke(ctx.actor) end,
        fn -> render_click(view, "open_create", %{}) end
      )

    assert_receive {:settings_read_probe, ^ref}
    assert_redirect(view, "/users/sign_in")
    assert place_snapshot(ctx.actor) == before
  end

  test "dialog changeset admission handles an unavailable second account read", ctx do
    {:ok, view, _} = live(NativePlaces.conn(ctx.actor), "/places")
    render_click(view, "open_edit", %{"id" => "118701"})
    socket = :sys.get_state(view.pid).socket
    before = place_snapshot(ctx.actor)
    prior_repo = Repo.get_dynamic_repo()

    try do
      {refused, ref} =
        SettingsReadProbe.run(
          self(),
          "SELECT id,name,icon,color FROM tags",
          fn -> Repo.put_dynamic_repo(:unavailable_dialog_account_repo) end,
          fn -> Form.open(socket, :create, nil) end
        )

      assert_receive {:settings_read_probe, ^ref}
      assert refused.assigns.form_state == nil
      assert refused.assigns.place_data == nil
      assert refused.assigns.detail == nil
      assert refused.assigns.note_state == nil
      assert refused.assigns.confirmation == nil
      assert refused.assigns.error != nil
    after
      Repo.put_dynamic_repo(prior_repo)
    end

    assert place_snapshot(ctx.actor) == before
  end

  defp assert_cleared(view) do
    assigns = :sys.get_state(view.pid).socket.assigns

    for key <- [:form_state, :place_data, :detail, :note_state, :confirmation, :nearby_state],
        do: assert(assigns[key] == nil)
  end

  defp place_snapshot(actor),
    do: {
      Repo.query!(
        "SELECT id,name,note,updated_at FROM places WHERE user_id=$1 ORDER BY id",
        [actor.id],
        log: false
      ).rows,
      Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
    }
end
