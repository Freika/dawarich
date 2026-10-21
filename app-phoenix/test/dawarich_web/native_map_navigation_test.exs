defmodule DawarichWeb.NativeMapNavigationTest do
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
      email: "map-nav-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id}
  end

  test "back and forward restore range import panel and selected day", %{id: id} do
    {:ok, view, _} = open(id, @first)
    first = state(view)

    assert first["url"] == %{
             "start_at" => "2026-03-29T00:00",
             "end_at" => "2026-03-29T23:59",
             "import_id" => "7",
             "panel" => "timeline",
             "date" => "2026-03-29"
           }

    assert_push_event(view, "map:config", %{
      revision: 1,
      range: %{importId: "7", startAt: "2026-03-29T00:00:00+01:00"}
    })

    render_patch(view, @second)

    assert state(view)["url"] == %{
             "start_at" => "2026-03-30T00:00",
             "end_at" => "2026-03-30T23:59"
           }

    assert state(view)["revision"] == 2

    render_patch(view, @first)
    assert state(view)["url"] == first["url"]
    assert state(view)["revision"] == 3
    assert_push_event(view, "map:config", %{revision: 3, range: %{importId: "7"}})

    view |> element("a#native-map-next-day") |> render_click()
    assert state(view)["url"]["start_at"] =~ "2026-03-30T00:00"
    assert state(view)["url"]["import_id"] == "7"
    assert state(view)["url"]["panel"] == "timeline"
  end

  test "rapid date patches cannot apply old map data", %{id: id} do
    {:ok, view, _} = open(id, @second)
    assert_push_event(view, "map:config", %{revision: 1})

    assert %{revision: 2} =
             render_hook(view, "map:range", %{
               "startAt" => "2026-04-01T00:00",
               "endAt" => "2026-04-01T23:59"
             })
             |> then(fn _ -> reply(view) end)

    assert %{revision: 3} =
             render_hook(view, "map:range", %{
               "startAt" => "2026-04-02T00:00",
               "endAt" => "2026-04-02T23:59",
               "importId" => "9"
             })
             |> then(fn _ -> reply(view) end)

    assert_push_event(view, "map:config", %{revision: 2})
    assert_push_event(view, "map:config", %{revision: 3, range: %{importId: "9"}})

    assert state(view)["url"] == %{
             "start_at" => "2026-04-02T00:00",
             "end_at" => "2026-04-02T23:59",
             "import_id" => "9"
           }

    render_hook(view, "map:range", %{
      "startAt" => "2026-04-02T00:00",
      "endAt" => "2026-04-02T23:59",
      "importId" => "9"
    })

    assert_reply(view, %{revision: 3})
    render_hook(view, "map:range", %{"startAt" => ["x"], "endAt" => "y"})
    assert_reply(view, %{error: "invalid_range"})
    assert state(view)["revision"] == 3
  end

  test "panel reopening does not reset replay", %{id: id} do
    {:ok, view, _} = open(id, @second)
    assert_push_event(view, "map:config", %{revision: 1})

    render_hook(view, "map:panel", %{"panel" => "timeline"})
    assert state(view)["url"]["panel"] == "timeline"
    render_hook(view, "map:panel", %{"panel" => ""})
    refute Map.has_key?(state(view)["url"], "panel")
    render_patch(view, @second <> "&date=2026-03-30")
    assert state(view)["revision"] == 1
    refute_push_event(view, "map:config", %{})
  end

  defp reply(view) do
    assert_reply(view, reply)
    reply
  end

  defp state(view),
    do:
      view
      |> element("#state")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> Jason.decode!()

  defp open(id, path) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: "/map/v2",
      path_info: ["map", "v2"],
      query_string: URI.parse(path).query
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeMapShellRouter.call([])
    |> live()
  end
end
