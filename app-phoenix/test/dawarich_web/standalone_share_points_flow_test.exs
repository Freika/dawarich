defmodule DawarichWeb.StandaloneSharePointsFlowTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "share-flow@dawarich.test",
        settings: %{"timezone" => "UTC", "locale" => "en"}
      })

    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag :sweep_shared_timestamp_ties
  test "standalone timeline creation returns tied points and Rails stride sampling", c do
    page =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> get("/share_links/timeline/new")

    assert page.status == 200

    [token] =
      page.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("form[action='/share_links/timeline'] input[name=authenticity_token]")
      |> LazyHTML.attribute("value")

    created =
      RailsFormRequests.post_form(
        c.session,
        URI.encode_query(%{
          "authenticity_token" => token,
          "shared_link[name]" => "Synthetic timeline",
          "shared_link[start_date]" => "2026-05-09",
          "shared_link[end_date]" => "2026-05-09"
        }),
        [{"accept", "text/html"}],
        "/share_links/timeline"
      )

    assert created.status == 302
    [[id]] = Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.actor.id]).rows
    ts = DateTime.to_unix(~U[2026-05-09 12:00:00Z])
    points!(c.actor.id, ts, 2)
    points!(c.actor.id, ts - 86400, 1)
    points!(user!(), ts, 1)

    Repo.query!(
      "INSERT INTO points(user_id,timestamp,anomaly,lonlat,created_at,updated_at) VALUES($1,$2,true,ST_SetSRID(ST_MakePoint(14,53),4326)::geography,now(),now())",
      [c.actor.id, ts]
    )

    public = get(build_conn(), "/s/" <> id)
    assert public.status == 200
    assert public.resp_body =~ ~s(data-controller="shared-trip-map")
    response = points_response(id)
    assert response.status == 200

    assert Enum.sort(Jason.decode!(response.resp_body)) == [
             [13.000001, 52.0, ts],
             [13.000002, 52.0, ts]
           ]

    assert get_resp_header(response, "cache-control") == ["max-age=30, public"]

    points!(c.actor.id, ts, 9999)
    sampled = points_response(id)
    assert sampled.status == 200
    sampled_rows = Jason.decode!(sampled.resp_body)
    assert length(sampled_rows) == 5001

    assert Enum.all?(sampled_rows, fn [lon, lat, timestamp] ->
             lon > 13 and lon < 14 and lat == 52.0 and timestamp == ts
           end)
  end

  @tag :sweep_shared_live_ties
  test "standalone live current position and route accept latest timestamp ties", c do
    ts = System.os_time(:second)
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO shared_links(id,user_id,resource_type,name,settings,created_at,updated_at) VALUES($1::text::uuid,$2,3,'Synthetic live',$3,$4,$4)",
      [id, c.actor.id, %{"show_route" => true}, DateTime.to_naive(DateTime.from_unix!(ts - 1))]
    )

    points!(c.actor.id, ts, 2)
    response = points_response(id)
    assert response.status == 200
    assert [latest] = Jason.decode!(response.resp_body)
    assert latest in [[13.000001, 52.0, ts], [13.000002, 52.0, ts]]

    route =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/shared/" <> id <> "/route")

    assert route.status == 200

    assert Enum.sort(Jason.decode!(route.resp_body)) == [
             [13.000001, 52.0, ts],
             [13.000002, 52.0, ts]
           ]
  end

  defp points_response(id),
    do:
      build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/shared/" <> id <> "/points")

  defp points!(user, ts, count) do
    Repo.query!(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) SELECT $1,$2,ST_SetSRID(ST_MakePoint(13 + (n + (SELECT count(*) FROM points WHERE user_id=$1 AND timestamp=$2))*0.000001,52),4326)::geography,now(),now() FROM generate_series(1,$3::integer) n",
      [user, ts, count]
    )
  end
end
