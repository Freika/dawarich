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

    %{uuid: uuid, id: id}
  end

  test "native public GET counts once while HEAD and LiveView reconnect are read only", %{
    uuid: uuid
  } do
    path = "/s/#{uuid}"

    count = fn ->
      Repo.query!("SELECT view_count FROM shared_links WHERE id=$1", [Ecto.UUID.dump!(uuid)],
        log: false
      ).rows
    end

    assert build_conn() |> head(path) |> Map.get(:status) == 200
    before = count.()
    assert before == [[0]]
    assert build_conn() |> get(path) |> Map.get(:status) == 200
    assert count.() == [[(hd(hd(before)) || 0) + 1]]

    conn =
      build_conn() |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}}) |> get(path)

    {:ok, view, _} = live(conn)
    after_join = count.()
    render(view)
    render_hook(view, "public:ready", %{"revision" => 1})
    assert count.() == after_join
    assert build_conn() |> head(path) |> Map.get(:status) == 200
    assert count.() == after_join
  end

  test "public HTTP refuses unknown revoked and locked links with source statuses", %{uuid: uuid} do
    assert get(build_conn(), "/s/#{Ecto.UUID.generate()}").status == 404
    rows("UPDATE shared_links SET magic_phrase='synthetic-status-phrase' WHERE id=$1::text::uuid", [uuid])
    locked = get(build_conn(), "/s/#{uuid}")
    assert locked.status == 401
    assert locked.resp_body =~ "public-phrase"
    rows("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [uuid])
    revoked = get(build_conn(), "/s/#{uuid}")
    assert revoked.status == 404
    assert revoked.resp_body =~ "no longer available"
  end

  test "native family public navigation rechecks audience without disclosing missing or revoked resources",
       %{uuid: uuid, id: id} do
    viewer = id + 1

    RailsUser.insert!(%{
      id: viewer,
      email: "native-family-#{viewer}@dawarich.test",
      theme: "light"
    })

    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{id: id, creator_id: id, name: "Native family", created_at: stamp, updated_at: stamp}
    ])

    Repo.insert_all(
      "family_memberships",
      for(
        {member, role} <- [{id, 0}, {viewer, 1}],
        do: %{
          id: member,
          family_id: id,
          user_id: member,
          role: role,
          created_at: stamp,
          updated_at: stamp
        }
      )
    )

    rows("UPDATE users SET plan=2,active_until=$2 WHERE id=$1", [
      id,
      DateTime.utc_now() |> DateTime.add(30, :day)
    ])

    rows("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      uuid,
      %{"audience" => "family", "family_id" => to_string(id)}
    ])

    scope = Dawarich.Maps.principal(Dawarich.Accounts.get(viewer), "en")
    assert {:ok, _} = Dawarich.Maps.Public.config(%{id: uuid, viewer_scope: scope})

    assert {:ok, _} =
             Dawarich.Maps.Public.presentation(%{id: uuid, viewer_scope: scope})

    conn = RailsUser.signed_in(viewer) |> RailsUser.connecting_as(viewer) |> get("/s/#{uuid}")
    assert conn.status == 200
    assert String.contains?(conn.resp_body, "mobile-navigation-menu") == true
    assert String.contains?(conn.resp_body, ~s(data-theme="dawarich")) == true
    assert String.contains?(conn.resp_body, "utm_medium=public_share") == false
    assert String.contains?(conn.resp_body, "data-controller") == false

    assert LazyHTML.from_document(conn.resp_body)
           |> LazyHTML.query(~s(meta[property="og:title"]))
           |> LazyHTML.attribute("content") == ["Native public trip"]

    {:ok, view, _} = live(conn)
    render_hook(view, "changelog_consent", %{"decision" => "granted"})
    assert rows("SELECT changelog_consent FROM users WHERE id=$1", [viewer]) == [[1]]
    rows("DELETE FROM trips WHERE id=$1", [id * 10])
    missing = RailsUser.signed_in(viewer) |> get("/s/#{uuid}")
    assert String.contains?(missing.resp_body, "mobile-navigation-menu") == true
    assert String.contains?(missing.resp_body, "native-public-map") == false
    assert String.contains?(missing.resp_body, "Native public trip") == false
    rows("DELETE FROM family_memberships WHERE user_id=$1", [viewer])
    render_hook(view, "changelog_consent", %{"decision" => "declined"})
    assert rows("SELECT changelog_consent FROM users WHERE id=$1", [viewer]) == [[1]]
    revoked = RailsUser.signed_in(viewer) |> get("/s/#{uuid}")
    assert String.contains?(revoked.resp_body, "mobile-navigation-menu") == false
    assert String.contains?(revoked.resp_body, "native-public-map") == false
    assert String.contains?(revoked.resp_body, "Native public trip") == false
  end

  test "native public presentation keeps localized metadata and marketing navigation", %{
    uuid: uuid
  } do
    conn = get(build_conn(), "/s/#{uuid}")
    document = LazyHTML.from_document(conn.resp_body)
    title = DawarichWeb.SharedPages.title(%{locale: "en", link: %{name: "Native public trip"}})

    assert LazyHTML.query(document, "title") |> LazyHTML.text() ==
             DawarichWeb.Layouts.page_title("en", title)

    assert LazyHTML.query(document, ~s(meta[property="og:title"]))
           |> LazyHTML.attribute("content") == ["Native public trip"]

    assert String.contains?(conn.resp_body, "utm_content=header") == true
    assert String.contains?(conn.resp_body, "utm_content=footer_cta") == true
    assert String.contains?(conn.resp_body, "mobile-navigation-menu") == false
  end

  test "native public documents and refusals are nonindexable and never stored", %{uuid: uuid} do
    for path <- ["/s/#{uuid}", "/s/missing-native-grant", "/map/v2"] do
      conn = get(build_conn(), path)
      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
      assert Plug.Conn.get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "native public resource preserves descriptions day selection and flag refusals", %{
    uuid: uuid,
    id: id
  } do
    rows(
      "INSERT INTO action_text_rich_texts(name,body,record_type,record_id,created_at,updated_at) VALUES('description',$1,'Trip',$2,now(),now())",
      ["<div>Native shared description</div>", id * 10]
    )

    conn =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> get("/s/#{uuid}")

    {:ok, view, _} = live(conn)
    assert has_element?(view, "#native-public-resource", "Native shared description")

    days =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-public-day]")
      |> LazyHTML.attribute("data-public-day")

    assert days != []
    first = hd(days)

    view
    |> element("[data-public-day='#{first}'] button[phx-click='public:day']")
    |> render_click()

    assert_push_event(view, "public:day", %{day: first})
    assert has_element?(view, "[data-public-day='#{first}'][data-public-day-selected=true]")

    rows("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      uuid,
      %{"show_description" => false, "show_route" => false, "show_days" => false}
    ])

    send(view.pid, :refresh)
    refute has_element?(view, "#native-public-resource", "Native shared description")
    refute has_element?(view, "[data-public-day]")
    refute has_element?(view, "#native-public-map")
    refute render(view) =~ "data-controller"
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
    assert locked.status == 401
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

    html = html_response(conn, 401)
    assert html =~ "action=\"/s/#{uuid}/unlock\""
    refute html =~ "id=\"native-public-map\""
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
