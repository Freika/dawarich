defmodule DawarichWeb.NativeM6HostTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  @first "/map/v2?start_at=2026-03-29T00:00&end_at=2026-03-29T23:59&import_id=7&panel=timeline&date=2026-03-29"
  @second "/map/v2?start_at=2026-03-30T00:00&end_at=2026-03-30T23:59"

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "m6-integration-#{id}@dawarich.test",
      api_key: "synthetic-m6-host-key",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id}
  end

  test "native production host restores range import panel and day on back and forward", %{id: id} do
    {:ok, view, html} = open(id, @first)
    assert has_element?(view, "#native-map[phx-hook=Map]")
    refute html =~ "synthetic-m6-host-key"
    assert config(view)["revision"] == 1
    assert config(view)["range"]["importId"] == "7"
    render_patch(view, @second)
    assert_patch(view, @second)
    assert config(view)["revision"] == 2
    render_patch(view, @first)
    assert_patch(view, @first)
    assert config(view)["revision"] == 3
    view |> element("#native-map-next-day") |> render_click()
    path = assert_patch(view)
    assert path =~ "import_id=7"
    assert path =~ "panel=timeline"
    assert path =~ "date=2026-03-29"

    render_hook(view, "map:range", %{
      "startAt" => "2026-04-01T00:00",
      "endAt" => "2026-04-01T23:59"
    })

    assert_reply(view, %{revision: 5})
    assert config(view)["revision"] == 5
  end

  defp config(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#native-map")
    |> LazyHTML.attribute("data-map-config")
    |> hd()
    |> Jason.decode!()
  end

  defp open(id, path) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: "/map/v2",
      path_info: ["map", "v2"],
      query_string: URI.parse(path).query || ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
