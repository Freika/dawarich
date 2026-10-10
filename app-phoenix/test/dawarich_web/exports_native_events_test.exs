defmodule DawarichWeb.ExportsNativeEventsTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint
  setup do
    user = RailsUser.insert!(%{id: 11101, email: "export-native@example.invalid"})
    other = RailsUser.insert!(%{id: 11102, email: "export-other@example.invalid"})

    ImportsExportsSeeds.export!(%{
      id: 111_010,
      user_id: user.id,
      status: 0,
      name: "native-export.json"
    })

    ImportsExportsSeeds.export!(%{
      id: 111_020,
      user_id: other.id,
      status: 2,
      name: "foreign-export.json"
    })

    Dawarich.Jobs.Ownership.put!(Repo, "command:exports.points", :oban)
    %{user: user}
  end

  defp live_as(user),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/exports")

  test "export progress refreshes on reconnect and refuses a revoked socket", c do
    {:ok, view, _} = live_as(c.user)
    Repo.query!("UPDATE exports SET status=1 WHERE id=111010", [], log: false)
    Dawarich.Exports.Events.broadcast(c.user.id)
    assert has_element?(view, "#export_111010", "Processing")

    Repo.query!(
      "UPDATE exports SET status=3,error_message='synthetic failure' WHERE id=111010",
      [],
      log: false
    )

    {:ok, reopened, _} = live_as(c.user)
    assert has_element?(reopened, "#export_111010", "Failed")
    socket = :sys.get_state(reopened.pid).socket

    Repo.query!("UPDATE users SET encrypted_password='export-revoked' WHERE id=$1", [c.user.id],
      log: false
    )

    send(reopened.pid, {:domain_changed, c.user.id, :exports})
    assert_redirect(reopened, "/users/sign_in")
    assert {:halt, cleared} = DawarichWeb.NativeJobsAuth.authorize(socket)
    assert cleared.assigns.entries == []

    assert {:noreply, refused} =
             DawarichWeb.ExportsLive.Index.handle_info(
               {:domain_changed, c.user.id, :exports},
               socket
             )

    assert refused.assigns.entries == []
    assert refused.assigns.delete_target == nil
    assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
  end

  test "native export delete confirms once and foreign ids do nothing", c do
    {:ok, view, _} = live_as(c.user)
    assert has_element?(view, ~s(#export_111010 button[aria-label="Delete export"]))
    render_hook(view, "confirm_export_delete", %{"id" => "111010"})
    assert [[1]] = rows("SELECT count(*) FROM exports WHERE id=111010")
    render_hook(view, "choose_export_delete", %{"id" => "111020"})
    assert :sys.get_state(view.pid).socket.assigns.delete_target == nil
    render_hook(view, "choose_export_delete", %{"id" => "111010"})
    assert has_element?(view, "#export-delete-dialog[open]")
    render_hook(view, "cancel_export_delete", %{})
    render_hook(view, "confirm_export_delete", %{})
    assert [[1]] = rows("SELECT count(*) FROM exports WHERE id=111010")
    render_hook(view, "choose_export_delete", %{"id" => "111010"})
    Repo.query!("UPDATE exports SET user_id=11102 WHERE id=111010", [], log: false)
    render_hook(view, "confirm_export_delete", %{"id" => "111020"})
    assert [[1]] = rows("SELECT count(*) FROM exports WHERE id=111010")
    Repo.query!("UPDATE exports SET user_id=11101 WHERE id=111010", [], log: false)
    render_hook(view, "choose_export_delete", %{"id" => "111010"})
    render_hook(view, "confirm_export_delete", %{"id" => "111020"})
    render_hook(view, "confirm_export_delete", %{})
    assert rows("SELECT id FROM exports ORDER BY id") == [[111_020]]

    assert [[1]] =
             rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.EventsWorker'"
             )

    assert render(view) =~ "Export was successfully destroyed"
    refute has_element?(view, "[data-turbo-method], turbo-frame")
  end
end
