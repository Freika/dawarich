defmodule DawarichWeb.NativePointCommandsTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    [id, other] = for _ <- 1..2, do: System.unique_integer([:positive])

    for user <- [id, other],
        do:
          RailsUser.insert!(%{
            id: user,
            email: "pc-#{user}@dawarich.test",
            settings: %{"timezone" => "UTC"}
          })

    %{id: id, other: other}
  end

  test "point commands reply typed move conflict and delete results", c do
    own = point!(c.id)
    foreign = point!(c.other)
    view = open(c.id)
    scope = %{"start_at" => "2026-09-28T00:00Z", "end_at" => "2026-09-29T00:00Z"}

    move = fn id, revision ->
      %{
        "point_id" => to_string(id),
        "point" => %{"latitude" => "51", "longitude" => "14", "revision" => revision},
        "history_scope" => scope
      }
    end

    render_hook(view, "point:move", move.(own, 0))
    assert_reply(view, %{ok: true, response: %{"revision" => %{"point" => 1}}})
    render_hook(view, "point:move", move.(own, 0))
    assert_reply(view, %{error: "stale", response: %{"revision" => %{"point" => 1}}})
    render_hook(view, "point:move", move.(foreign, 0))
    assert_reply(view, %{error: "not_found"})
    assert rows("SELECT lock_version FROM points WHERE id=$1", [foreign]) == [[0]]

    render_hook(view, "point:delete", %{"point_id" => to_string(foreign)})
    assert_reply(view, %{error: "not_found"})
    render_hook(view, "point:delete", %{"point_id" => to_string(own)})
    assert_reply(view, %{ok: true})
    assert_push_event(view, "map:invalidate", %{resource: "points"})
    assert rows("SELECT count(*) FROM points WHERE id IN ($1,$2)", [own, foreign]) == [[1]]
  end

  defp point!(user),
    do:
      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1790593200,'POINT(13.4 52.5)',now(),now()) RETURNING id",
        [user]
      )
      |> hd()
      |> hd()

  defp open(id) do
    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{request_path: "/map/v2", path_info: ["map", "v2"], query_string: ""})
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeMapShellRouter.call([])
      |> live()

    view
  end
end
