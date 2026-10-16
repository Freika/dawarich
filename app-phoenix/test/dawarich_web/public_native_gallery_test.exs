defmodule DawarichWeb.PublicNativeGalleryTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.{Repo, SharedLinks}
  alias Dawarich.Photos.ProviderCache
  alias Dawarich.SharedApi.Photos
  alias Dawarich.Test.{SharingSeeds, TripsSeeds}
  @endpoint DawarichWeb.Endpoint
  @id "ac900000-0000-4000-8000-000000000003"
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    SharingSeeds.load!()
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    TripsSeeds.trip!(%{id: 189_003, user_id: 9901})
    TripsSeeds.shared_link!(%{id: @id, user_id: 9901, resource_type: 0, trip_id: 189_003})

    Repo.query!(
      "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
      [@id, %{"show_photos" => true}],
      log: false
    )

    Repo.query!(
      "INSERT INTO places(id,user_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES(189003,9901,'Synthetic private',53,14,ST_SetSRID(ST_MakePoint(14,53),4326)::geography,NOW(),NOW())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO tags(id,user_id,name,privacy_radius_meters,created_at,updated_at) VALUES(189003,9901,'Synthetic private',500,NOW(),NOW())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(189003,'Place',189003,NOW(),NOW())",
      [],
      log: false
    )

    link = SharedLinks.active(@id, DateTime.utc_now())
    %{range: {from, to}} = Photos.grant_context(link)
    key = "photos_search/#{link.user_id}/v2/#{from}/#{to}"

    photos =
      for {id, lat, lon} <- [{"visible-photo", 51.0, 12.0}, {"private-photo", 53.0, 14.0}],
          do: %{
            "id" => id,
            "latitude" => lat,
            "longitude" => lon,
            "source" => "immich",
            "localDateTime" => "2026-05-10T12:00:00Z"
          }

    assert {:ok, _} = ProviderCache.put(key, photos, 60)
    on_exit(fn -> Dawarich.Redis.cache_command(["UNLINK", key]) end)
    :ok
  end

  test "public day galleries load on expansion clear on collapse and reopen with only authorized photos" do
    conn = get(build_conn(), "/s/" <> @id)

    {:ok, view, html} =
      live(put_private(conn, :live_view_connect_info, %{session: get_session(conn)}))

    refute has_element?(view, "#native-public-resource img")
    refute String.contains?(html, "private-photo")
    render_hook(view, "public:gallery", %{"day" => "2026-05-10", "open" => true})
    assert has_element?(view, "details[data-public-day='2026-05-10'] img[src*='visible-photo']")
    refute has_element?(view, "img[src*='private-photo']")
    render_hook(view, "public:gallery", %{"day" => "2026-05-10", "open" => false})
    refute has_element?(view, "#native-public-resource img")
    render_hook(view, "public:gallery", %{"day" => "2026-05-10", "open" => true})
    assert has_element?(view, "details[data-public-day='2026-05-10'] img[src*='visible-photo']")
    render_hook(view, "public:gallery", %{"day" => "2099-01-01", "open" => true})
    refute has_element?(view, "details[data-public-day='2099-01-01']")

    Repo.query!(
      "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
      [@id, %{"show_photos" => false}], log: false)

    render_hook(view, "public:gallery", %{"day" => "2026-05-10", "open" => true})
    refute has_element?(view, "#native-public-resource img")
  end

  test "native public map gallery retains authorized photos and clears private or disabled photo delivery" do
    conn = get(build_conn(), "/s/" <> @id)
    assert conn.status == 200
    result = live(put_private(conn, :live_view_connect_info, %{session: get_session(conn)}))
    assert elem(result, 0) == :ok
    {:ok, view, html} = result
    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.public_error == nil
    page = assigns.public_presentation
    assert Enum.map(page.resource.photos, & &1["id"]) == ["visible-photo"]

    render_hook(view, "public:gallery", %{"day" => "2026-05-10", "open" => true})
    assert has_element?(view, "details[data-public-day='2026-05-10'] img[src*='visible-photo']")

    assert !String.contains?(html, "private-photo")
    assert !String.contains?(html, "data-controller")

    Repo.query!(
      "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
      [@id, %{"show_photos" => false}],
      log: false
    )

    send(view.pid, {:share_changed, @id, :disabled})
    render(view)
    assert :sys.get_state(view.pid).socket.assigns.public_presentation == nil
    conn = get(build_conn(), "/s/" <> @id)
    result = live(put_private(conn, :live_view_connect_info, %{session: get_session(conn)}))
    assert elem(result, 0) == :ok
    {:ok, disabled, _} = result
    assert :sys.get_state(disabled.pid).socket.assigns.public_presentation.resource.photos == []
    refute has_element?(disabled, "#native-public-resource img")
  end
end
