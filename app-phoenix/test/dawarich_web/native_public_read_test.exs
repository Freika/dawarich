defmodule DawarichWeb.NativePublicReadTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Repo, RailsCookies, RailsSecret}
  alias DawarichWeb.SharedLinkCookie
  alias Dawarich.Test.TripsSeeds
  @endpoint DawarichWeb.Endpoint
  @id "a1320000-0000-4000-8000-000000000002"
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    TripsSeeds.user!(881_322, %{"timezone" => "UTC", "immich_api_key" => "synthetic-provider-key"})

    TripsSeeds.trip!(%{id: 8_813_221, user_id: 881_322})

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        user_id: 881_322,
        resource_type: 0,
        resource_id: 8_813_221,
        name: "Native read",
        magic_phrase: "synthetic-read-phrase",
        settings: %{"show_photos" => false},
        created_at: ~N[2026-10-09 00:00:00],
        updated_at: ~N[2026-10-09 00:00:00]
      }
    ])

    :ok
  end

  defp read(action, opts \\ []) do
    conn = build_conn()

    conn =
      if opts[:unlocked] == false,
        do: conn,
        else:
          put_req_cookie(
            conn,
            "shared_link_#{@id}",
            RailsCookies.encrypt(
              SharedLinkCookie.unlock_token(@id, "synthetic-read-phrase"),
              "shared_link_#{@id}",
              RailsSecret.fetch(),
              opts[:expiry] || DateTime.add(DateTime.utc_now(), 3600)
            )
          )

    conn = if opts[:origin], do: put_req_header(conn, "origin", opts[:origin]), else: conn
    dispatch(conn, @endpoint, opts[:method] || :get, "/native/public/maps/#{@id}/#{action}")
  end

  test "native public reads admit the exact unlock cookie without owner credentials" do
    conn = read("metadata")
    assert conn.status == 200
    config = Jason.decode!(conn.resp_body)
    assert config["shareId"] == @id
    refute conn.resp_body =~ "synthetic-provider-key"
    refute conn.resp_body =~ "synthetic-read-phrase"
    refute conn.resp_body =~ "user_id"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "vary") == ["Cookie"]
    assert read("metadata", method: :head).resp_body == ""
  end

  test "expired revoked or re-locked public HTTP reads refuse before data" do
    assert read("points", unlocked: false).status == 401
    assert read("points", expiry: ~U[2020-01-01 00:00:00Z]).status == 401
    Repo.query!("UPDATE shared_links SET magic_phrase='rotated' WHERE id=$1::text::uuid", [@id])
    assert read("points").status == 401
    Repo.query!("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [@id])
    assert read("points").status == 404
  end

  test "show_photos false never loads photo bytes on native public reads" do
    assert read("photos").resp_body == "[]"
    assert read("photos/foreign/thumbnail?source=immich").status == 404
  end

  test "disabled public trip route refuses points after a positive native read" do
    TripsSeeds.point!(%{id: 8_813_225, user_id: 881_322, timestamp: 1_778_364_000, at: [13, 52]})
    assert Jason.decode!(read("points").resp_body) == [[13.0, 52.0, 1_778_364_000]]

    Repo.query!(
      "UPDATE shared_links SET settings=jsonb_set(settings,'{show_route}','false') WHERE id=$1::text::uuid",
      [@id],
      log: false
    )

    assert Jason.decode!(read("metadata").resp_body)["routeEnabled"] == false
    for action <- ~w(points route) do
      conn = read(action)
      assert conn.status == 200
      assert conn.resp_body == "[]"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end
  end

  test "native public read guard rejects writes origins and credentials" do
    assert read("metadata", method: :post).status == 405
    assert read("metadata", origin: "https://foreign.invalid").status == 403
    assert read("metadata?api_key=synthetic-secret").status == 400
  end

  test "native public points retain the source privacy zone exclusion" do
    TripsSeeds.point!(%{id: 8_813_222, user_id: 881_322, timestamp: 1_778_364_000, at: [13, 52]})
    TripsSeeds.point!(%{id: 8_813_223, user_id: 881_322, timestamp: 1_778_364_100, at: [14, 53]})

    Repo.query!(
      "INSERT INTO places (id,user_id,name,latitude,longitude,created_at,updated_at) VALUES (881322,$1,'Private',52,13,now(),now())",
      [881_322]
    )

    Repo.query!(
      "INSERT INTO tags (id,user_id,name,privacy_radius_meters,created_at,updated_at) VALUES (881322,$1,'Private',1000,now(),now())",
      [881_322]
    )

    Repo.query!(
      "INSERT INTO taggings (tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES (881322,'Place',881322,now(),now())"
    )

    points = Jason.decode!(read("points").resp_body)
    assert points == [[14.0, 53.0, 1_778_364_100]]
  end
end
