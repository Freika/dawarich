defmodule DawarichWeb.PointsNativeLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{NativeAdminUI, FrameSeeds}
  @endpoint DawarichWeb.Endpoint
  @params %{"start_at" => "1772359200", "end_at" => "1772362200", "order_by" => "asc"}
  @path "/points?start_at=1772359200&end_at=1772362200&order_by=asc"

  setup do
    %{target: user} = NativeAdminUI.setup!()
    for i <- 0..50, do: FrameSeeds.point!(user.id, 160_000 + i, 1_772_359_200 + i * 60)
    %{user: user}
  end

  test "point range order and pagination survive patch back and forward", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    view |> form("#point_filters", @params) |> render_submit()
    patch = assert_patch(view)
    assert URI.decode_query(URI.parse(patch).query)["order_by"] == "asc"
    assert URI.decode_query(URI.parse(patch).query)["start_at"] == @params["start_at"]
    render_patch(view, @path <> "&page=2")
    assert has_element?(view, "#point_160050")
    refute has_element?(view, "#point_160000")
    render_patch(view, @path)
    assert has_element?(view, "#point_160000")
    render_patch(view, @path <> "&page=2")
    assert has_element?(view, "#point_160050")
    assert :sys.get_state(view.pid).socket.assigns.query["order_by"] == "asc"
  end

  test "localized point navigation retains filters and working export confirmation", %{user: user} do
    for {locale, export} <- [{"en", "Export"}, {"de", "Export"}] do
      {:ok, view, _} = live(NativeAdminUI.conn(user), @path <> "&locale=" <> locale)
      assert has_element?(view, "#point_160000")
      assert has_element?(view, "button[phx-click='export'][phx-value-format='json']", export)
      refute Map.has_key?(:sys.get_state(view.pid).socket.assigns.query, "locale")
      view |> element("button[phx-click='export'][phx-value-format='json']") |> render_click()
      assert has_element?(view, "#points_dialog_title", export)
      view |> element("#points_cancel") |> render_click()
      refute has_element?(view, "#points_dialog")
      view |> form("#point_filters", @params) |> render_submit()

      assert URI.decode_query(URI.parse(assert_patch(view)).query)["start_at"] ==
               @params["start_at"]

      assert has_element?(view, "#point_160000")
    end
  end

  test "older point query cannot replace a new filter", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    render_patch(view, @path <> "&page=2")
    socket = :sys.get_state(view.pid).socket
    old = {:points, 0, make_ref(), "old"}

    assert {:noreply, socket} =
             DawarichWeb.PointsLive.Index.handle_async(
               old,
               {:ok, %{rows: [%{id: 160_000}]}},
               socket
             )

    assert Enum.map(socket.assigns.rows, & &1.id) == [160_050]
  end

  test "point page retains at most fifty redacted rows", %{user: user} do
    {:ok, view, html} = live(NativeAdminUI.conn(user), @path)
    socket = :sys.get_state(view.pid).socket
    assert length(socket.assigns.rows) == 50
    refute :erlang.term_to_binary(socket.assigns) =~ user.api_key
    refute :erlang.term_to_binary(socket.assigns) =~ user.encrypted_password
    refute html =~ "data-controller"
    refute html =~ "turbo-frame"
    assert NativeAdminUI.labels(html) == []

    for page <- 1..5 do
      render_patch(view, @path <> "&page=#{page}")
      assert length(:sys.get_state(view.pid).socket.assigns.rows) <= 50
    end
  end

  test "point ordinary render does not read and invalid queries stay bounded", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    {_, queries} = NativeAdminUI.queries(fn -> NativeAdminUI.html(view) end)
    assert queries == []
    html = render_patch(view, @path <> "&order_by=invalid")
    assert html =~ NativeAdminUI.escaped("controllers.application.admin_action_failed")
    assert Process.alive?(view.pid)
    assert :sys.get_state(view.pid).socket.assigns.rows == []
  end
end
