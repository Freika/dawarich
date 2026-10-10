defmodule DawarichWeb.NativePublicMapTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, RailsCookies, RailsSecret}
  alias DawarichWeb.SharedLinkCookie
  alias Dawarich.Test.TripsSeeds
  @endpoint DawarichWeb.Endpoint
  @id "a1320000-0000-4000-8000-000000000001"
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    TripsSeeds.user!(881_321, %{"timezone" => "UTC"})

    TripsSeeds.trip!(%{
      id: 8_813_211,
      user_id: 881_321,
      path: [[13, 52], [14, 53]],
      started_at: ~N[2026-10-08 00:00:00],
      ended_at: ~N[2026-10-09 00:00:00]
    })

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        user_id: 881_321,
        resource_type: 0,
        resource_id: 8_813_211,
        name: "Public map",
        magic_phrase: "synthetic-public-phrase",
        settings: %{"show_photos" => false},
        created_at: ~N[2026-10-09 00:00:00],
        updated_at: ~N[2026-10-09 00:00:00]
      }
    ])

    :ok
  end

  defp open(unlocked \\ true, connection_unlocked \\ true) do
    now = DateTime.utc_now()
    token = SharedLinkCookie.unlock_token(@id, "synthetic-public-phrase")

    cookie =
      RailsCookies.encrypt(
        token,
        "shared_link_#{@id}",
        RailsSecret.fetch(),
        DateTime.add(now, 3600)
      )

    conn = Plug.Test.conn(:get, "/probe-public/#{@id}")

    conn =
      if unlocked, do: Plug.Test.put_req_cookie(conn, "shared_link_#{@id}", cookie), else: conn

    proofs = if connection_unlocked, do: SharedLinkCookie.proofs(conn, now), else: %{}

    conn =
      conn
      |> Plug.Conn.put_private(:live_view_connect_info, %{
        session: %{"rails_user_id" => nil, "shared_link_proofs" => proofs}
      })
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Plug.Conn.fetch_query_params()
      |> Plug.Conn.assign(:locale, "de")
      |> Dawarich.Test.NativePublicMapProbeRouter.call([])

    {:ok, view, html} = live(conn)
    {view, html, cookie}
  end

  test "native public host is secret-free and reconnect uses server cookie proof" do
    {view, html, cookie} = open()
    assert html =~ "phx-hook=\"PublicMap\""
    assert html =~ "Public map"
    state = inspect(:sys.get_state(view.pid), limit: :infinity)
    refute state =~ "synthetic-public-phrase"
    refute state =~ cookie
    refute html =~ "api_key"
    refute html =~ "features"
    render_hook(view, "map:ready", %{"revision" => 1})
    assert has_element?(view, "[data-map-ready=true]")
  end

  test "stale public ready callback cannot acknowledge the current host" do
    {view, _, _} = open()
    render_hook(view, "map:ready", %{"revision" => 0})
    refute has_element?(view, "[data-map-ready=true]")
    render_hook(view, "map:ready", %{"revision" => 1})
    assert has_element?(view, "[data-map-ready=true]")
  end

  test "re-locked public event clears the canvas and keeps phrase unlock HTTP" do
    {view, _, _} = open()
    Repo.query!("UPDATE shared_links SET magic_phrase='rotated' WHERE id=$1::text::uuid", [@id])
    render_hook(view, "map:ready", %{})
    refute has_element?(view, "#native-public-map")
    assert has_element?(view, "form[action='/s/#{@id}/unlock'][method=post]")
    refute has_element?(view, "form[phx-submit]")
    assert_push_event(view, "map:clear", %{code: "locked"})
  end

  test "queued public result after revocation cannot restore map data" do
    {view, _, _} = open()
    Repo.query!("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [@id])
    send(view.pid, :public_refresh)
    refute render(view) =~ "native-public-map"
    assert_push_event(view, "map:clear", %{code: "not_found"})
  end

  test "initial locked public host renders a native refusal without redirecting" do
    {view, html, _} = open(false)
    assert html =~ "/s/#{@id}/unlock"
    refute has_element?(view, "#native-public-map")
  end

  test "connected public mount cannot reuse an HTTP proof after its cookie disappears" do
    {view, _, _} = open(true, false)
    refute has_element?(view, "#native-public-map")
    assert has_element?(view, "form[action='/s/#{@id}/unlock']")
  end

  test "expiry callback belongs only to its current public grant revision" do
    {view, _, _} = open()
    active = :sys.get_state(view.pid).socket.assigns[:public_deadline]
    assert is_map(active)
    send(view.pid, {:public_map_expiry, make_ref()})
    render(view)
    assert :sys.get_state(view.pid).socket.assigns.public_deadline.token == active.token
    Repo.query!("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [@id])
    send(view.pid, {:public_map_expiry, active.token})
    render(view)
    assert :sys.get_state(view.pid).socket.assigns.public_deadline == nil
    refute has_element?(view, "#native-public-map")
  end

  test "public URL change cannot reuse another share capability" do
    {view, _, _} = open()
    render_patch(view, "/probe-public/a1320000-0000-4000-8000-000000000099")
    refute has_element?(view, "#native-public-map")
  end
end
