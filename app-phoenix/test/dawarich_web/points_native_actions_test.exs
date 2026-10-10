defmodule DawarichWeb.PointsNativeActionsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Accounts.Scope
  alias Dawarich.Points.Commands
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, NativeAdminUI}
  @endpoint DawarichWeb.Endpoint
  @params %{"start_at" => "1772359200", "end_at" => "1772362200", "order_by" => "asc"}
  @path "/points?start_at=1772359200&end_at=1772362200&order_by=asc"

  setup do
    %{target: user, actor: foreign} = NativeAdminUI.setup!()
    for i <- 0..50, do: FrameSeeds.point!(user.id, 180_000 + i, 1_772_359_200 + i * 60)
    FrameSeeds.point!(foreign.id, 190_000, 1_772_359_200)
    %{user: user, foreign: foreign, scope: Scope.for_user(user, "de")}
  end

  test "point deletion preserves filters and leaves foreign rows intact", %{
    user: user,
    scope: scope
  } do
    assert {:error, :unauthorized} = Commands.delete(scope, @params, ["190000"])
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    view |> element("#point_ids_180000") |> render_click()
    view |> element("[phx-click=confirm_delete]") |> render_click()
    view |> element("#points_confirm") |> render_click()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["order_by"] == "asc"
    assert URI.decode_query(URI.parse(path).query)["start_at"] == @params["start_at"]

    assert Repo.query!("SELECT id FROM points WHERE id=ANY($1)", [[180_000, 190_000]], log: false).rows ==
             [[190_000]]

    assert render(view) =~
             NativeAdminUI.escaped("controllers.points.points_were_successfully_destroyed")

    assert {:ok, %{notice: "controllers.points.no_points_selected"}} =
             Commands.delete(scope, @params, [])
  end

  test "point selection resets when the page changes and survives reconnect safely", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    view |> element("#select_all_points") |> render_click()
    assert MapSet.size(:sys.get_state(view.pid).socket.assigns.selected) == 50
    render_patch(view, @path <> "&page=2")
    assert :sys.get_state(view.pid).socket.assigns.selected == MapSet.new()
    refute has_element?(view, "#points_dialog")
    {:ok, reconnected, _} = live(NativeAdminUI.conn(user), @path <> "&page=2")
    assert :sys.get_state(reconnected.pid).socket.assigns.selected == MapSet.new()
    render_click(reconnected, "select_point", %{"id" => "190000"})
    assert :sys.get_state(reconnected.pid).socket.assigns.selected == MapSet.new()
  end

  test "M4 point export facade shares the native receipt and prepared time window", %{
    scope: scope
  } do
    receipt = Ecto.UUID.generate()
    assert {:ok, result} = Commands.request_export(scope, @params, "json", receipt)

    [[name, format, first, last]] =
      Repo.query!(
        "SELECT name,file_format,start_at,end_at FROM exports WHERE id=$1",
        [result.id],
        log: false
      ).rows

    prepared = %{name: name, file_format: format, start_at: first, end_at: last}
    assert {:ok, id} = Dawarich.Exports.request(scope, {:points, prepared, receipt})
    assert id == result.id
    proof = Dawarich.Accounts.Principal.scope(scope)

    Repo.query!(
      "UPDATE users SET encrypted_password='revoked-export-proof' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} =
             Dawarich.Exports.request(proof, {:points, prepared, receipt})
  end

  test "repeated export acknowledgement publishes one request", %{scope: scope, user: user} do
    receipt = Ecto.UUID.generate()
    assert {:ok, first} = Commands.request_export(scope, @params, "json", receipt)
    assert {:ok, second} = Commands.request_export(scope, @params, "json", receipt)
    assert first.id == second.id

    assert Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [user.id], log: false).rows ==
             [[1]]

    assert Repo.query!(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='exports.points' AND payload->>'user_id'=$1",
             [to_string(user.id)],
             log: false
           ).rows == [[1]]

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-identity-000000000000000000' WHERE id=$1",
      [user.id],
      log: false
    )

    assert {:error, :stale_session} = Commands.request_export(scope, @params, "json", receipt)
  end

  test "cancelled point action has no effects and failed export can retry", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    view |> element("#point_ids_180000") |> render_click()
    view |> element("[phx-click=confirm_delete]") |> render_click()
    view |> element("#points_cancel") |> render_click()

    assert Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [user.id], log: false).rows ==
             [[51]]

    render_click(view, "export", %{"format" => "bad"})

    assert Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [user.id], log: false).rows ==
             [[0]]

    render_click(view, "export", %{"format" => "json"})
    assert has_element?(view, "#points_dialog")
    view |> element("#points_confirm") |> render_click()
    render_click(view, "confirm_action", %{})

    assert Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [user.id], log: false).rows ==
             [[1]]
  end
end
