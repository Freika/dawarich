defmodule DawarichWeb.NativeM6PublicRoutesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])
    uuid = Ecto.UUID.generate()

    RailsUser.insert!(%{
      id: id,
      email: "public-route-#{id}@dawarich.test",
      api_key: "synthetic-public-route-key"
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Native public trip",
      path: [[13, 52], [14, 53]]
    })

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(uuid),
        user_id: id,
        resource_type: 0,
        resource_id: id * 10,
        name: "Native public trip",
        settings: %{"show_photos" => false},
        created_at: ~N[2026-10-01 00:00:00],
        updated_at: ~N[2026-10-01 00:00:00]
      }
    ])

    %{uuid: uuid}
  end

  test "production public route owns readiness and revocation without Hotwire or owner credentials",
       %{uuid: uuid} do
    conn =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> get("/s/#{uuid}")

    {:ok, view, html} = live(conn)
    assert has_element?(view, "#native-public-map[phx-hook=PublicMap]")
    assert has_element?(view, "#native-public-replay")

    for marker <- ~w(data-controller data-action importmap synthetic-public-route-key),
        do: refute(html =~ marker)

    render_hook(view, "map:ready", %{"revision" => 1})
    assert has_element?(view, "[data-map-ready=true]")
    rows("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [uuid])
    send(view.pid, :refresh)
    refute has_element?(view, "#native-public-map")
    assert_push_event(view, "map:clear", %{code: "not_found"})
  end

  test "a production public visit is counted once and locked visits are not counted", %{
    uuid: uuid
  } do
    assert rows("SELECT view_count FROM shared_links WHERE id=$1::text::uuid", [uuid]) == [[0]]

    conn =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> get("/s/#{uuid}")

    assert rows("SELECT view_count FROM shared_links WHERE id=$1::text::uuid", [uuid]) == [[1]]
    {:ok, view, _} = live(conn)
    render_hook(view, "map:ready", %{"revision" => 1})
    assert rows("SELECT view_count FROM shared_links WHERE id=$1::text::uuid", [uuid]) == [[1]]

    rows(
      "UPDATE shared_links SET magic_phrase='synthetic-locked-phrase' WHERE id=$1::text::uuid",
      [uuid]
    )

    locked = get(build_conn(), "/s/#{uuid}")
    assert locked.status == 200
    assert rows("SELECT view_count FROM shared_links WHERE id=$1::text::uuid", [uuid]) == [[1]]
  end

  test "production locked public route stays native and retains the HTTP phrase unlock", %{
    uuid: uuid
  } do
    rows(
      "UPDATE shared_links SET magic_phrase='synthetic-locked-phrase' WHERE id=$1::text::uuid",
      [uuid]
    )

    conn =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> get("/s/#{uuid}")

    {:ok, view, html} = live(conn)
    assert has_element?(view, "form[action='/s/#{uuid}/unlock'][method=post]")
    refute has_element?(view, "#native-public-map")
    refute html =~ "data-controller"
    refute html =~ "synthetic-locked-phrase"

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "POST",
             "/s/#{uuid}/unlock",
             "www.example.com"
           ).plug == DawarichWeb.SharedLinkPage
  end
end
