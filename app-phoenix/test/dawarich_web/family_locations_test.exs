defmodule DawarichWeb.FamilyLocationsTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @external_resource "test/fixtures/family_pages/consented_map_en.json"
  @now FrameSeeds.load_family("consented_map_en")["now"] |> DateTime.from_iso8601() |> elem(1)
  @endpoint DawarichWeb.Endpoint
  @path "/family/locations.json"

  defp freeze_clock(conn), do: Plug.Conn.assign(conn, :now, @now)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("consented_map_en"))
    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  defp locations(user),
    do:
      RailsUser.signed_in(user.id)
      |> freeze_clock()
      |> put_req_header("accept", "application/json")
      |> get(@path)

  test "family locations accepts verified browser session and returns private no store", ctx do
    conn = locations(ctx.owner)
    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    assert get_resp_header(conn, "etag") == []
    assert conn.private.phoenix_router == DawarichWeb.Router
    assert Enum.count(json_response(conn, 200)) == 1
  end

  test "family locations refuses guest no family and lapsed actors", ctx do
    guest =
      build_conn() |> freeze_clock() |> put_req_header("accept", "application/json") |> get(@path)

    assert guest.status == 401
    assert guest.resp_body == "[]"
    assert locations(ctx.outsider).status == 404
    System.put_env("SELF_HOSTED", "false")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)

    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      DateTime.add(@now, -1) |> DateTime.to_naive()
    ])

    Repo.query!("UPDATE users SET plan = 1 WHERE id = $1", [ctx.owner.id])

    for user <- [ctx.owner, ctx.member] do
      conn = locations(user)
      assert conn.status == 403
      assert conn.resp_body == "[]"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end
  end

  test "family location addresses normalize flat providers and obey reverse geocoding config",
       ctx do
    previous = System.get_env("PHOTON_API_HOST")

    on_exit(fn ->
      if previous,
        do: System.put_env("PHOTON_API_HOST", previous),
        else: System.delete_env("PHOTON_API_HOST")
    end)

    System.put_env("PHOTON_API_HOST", "synthetic.invalid")

    Repo.query!(
      "UPDATE points SET geodata=$1 WHERE user_id=90102",
      [%{"address" => %{"road" => "Main", "town" => "Leipzig", "country" => "Germany"}}],
      log: false
    )

    assert [%{"address" => "Main, Leipzig, Germany"}] = json_response(locations(ctx.owner), 200)
    System.delete_env("PHOTON_API_HOST")

    Repo.query!(
      "DELETE FROM instance_settings WHERE key IN ('photon_api_host','nominatim_api_host','geoapify_api_key','locationiq_api_key')",
      [],
      log: false
    )

    assert [%{"address" => nil}] = json_response(locations(ctx.owner), 200)
  end

  test "web projection preserves member email order and omits API only fields", ctx do
    conn = locations(ctx.owner)
    [member] = json_response(conn, 200)
    assert member["user_id"] == 90102

    assert Enum.sort(Map.keys(member)) ==
             ~w(address email latitude longitude name timestamp updated_at user_id)

    assert member["latitude"] == 51.3397
    assert member["longitude"] == 12.3731
    assert member["timestamp"] == 1_791_021_300
    assert member["updated_at"] == "2026-10-03T11:55:00.000+02:00"
    assert conn.resp_body =~ ~s([{"user_id":90102,"address":null,"email":)
    assert conn.resp_body =~ ~s("latitude":51.3397,"longitude":12.3731,"timestamp":1791021300,)
    refute conn.resp_body =~ "battery"
    refute conn.resp_body =~ "email_initial"

    Repo.query!(
      "UPDATE users SET settings = jsonb_set(settings, '{family,location_sharing,enabled}', 'false') WHERE id = 90102"
    )

    assert [%{"user_id" => 90101}] = json_response(locations(ctx.member), 200)
  end

  test "native Family HTML preserves member metadata without credentials or coordinates", ctx do
    html =
      RailsUser.signed_in(ctx.owner.id) |> freeze_clock() |> get("/family") |> html_response(200)

    refute html =~ "a9fpl-fixture-"
    refute html =~ "51.3397"
    refute html =~ "12.3731"
    refute html =~ "data-lat="
    refute html =~ "data-lon="
    doc = LazyHTML.from_document(html)

    assert ["Family"] ==
             doc |> LazyHTML.query("#native-family-map") |> LazyHTML.attribute("phx-hook")

    [config] =
      doc |> LazyHTML.query("#native-family-map") |> LazyHTML.attribute("data-map-config")

    config = Jason.decode!(config)

    for key <- ~w(locations api_key path geometry latitude longitude),
        do: refute(Map.has_key?(config, key))

    assert Enum.count(LazyHTML.query(doc, "[data-testid=family-last-seen]")) == 2

    assert Enum.count(LazyHTML.query(doc, "[data-native-family-member-id]")) == 2
    Repo.query!("DELETE FROM points WHERE user_id IN (90101, 90102)")

    empty =
      RailsUser.signed_in(ctx.owner.id)
      |> freeze_clock()
      |> get("/family")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert Enum.count(LazyHTML.query(empty, "[data-testid=family-last-seen]")) == 0
  end
end
