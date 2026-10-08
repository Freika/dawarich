defmodule DawarichWeb.PointDeleteTileVisibilityTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.Redis
  alias DawarichWeb.Api.{PointTilesController, PointWritesController}
  import Plug.Conn

  @at 1_735_689_600
  @params %{
    "z" => "10",
    "x" => "548",
    "y" => "338.mvt",
    "start_at" => "1735689600",
    "end_at" => "1735690000"
  }

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.delete_env("DAWARICH_RAILS")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    Dawarich.ApiEndpointCase.clear_transport_env()
    start_supervised!(hd(Redis.cache_child_specs()))
    :ok
  end

  test "coexistence single and bulk point deletion refresh cached tiles before retained follow-up" do
    for action <- [:destroy, :bulk_destroy] do
      id = user!(%{plan: 1, points_count: 1, settings: %{"timezone" => "UTC"}})

      user = %{
        id: id,
        timezone: "Etc/UTC",
        plan: 1,
        status: 1,
        active_until: nil,
        settings: %{"timezone" => "UTC"}
      }

      [[point]] =
        Repo.query!(
          "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now()) RETURNING id",
          [id, @at]
        ).rows

      first = tile(user)
      assert first.status == 200
      [etag] = get_resp_header(first, "etag")
      assert tile(user, etag).status == 304

      path =
        if action == :destroy, do: "/api/v1/points/#{point}", else: "/api/v1/points/bulk_destroy"

      params = if action == :destroy, do: %{}, else: %{"point_ids" => [point]}

      response =
        Plug.Test.conn(:delete, path)
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> assign(:api_user, user)
        |> assign(:api_params, params)
        |> assign(:api_context, %{self_hosted?: true})
        |> assign(:api_started, System.monotonic_time())
        |> assign(:api_headers, [])
        |> assign(:api_request_id, "point-delete-proof")
        |> assign(:api_vary, false)
        |> assign(:api_if_none_match, nil)
        |> Map.put(:path_params, %{"id" => to_string(point)})
        |> PointWritesController.call(action)

      assert response.status == 200
      assert [[0]] = rows("SELECT count(*) FROM points WHERE id=$1", [point])

      assert [["points.web_destroy_follow_up"]] =
               rows("SELECT kind FROM phoenix.rails_commands WHERE payload->>'user_id'=$1", [
                 to_string(id)
               ])

      refreshed = tile(user, etag)
      assert refreshed.status == 204
      refute get_resp_header(refreshed, "etag") == [etag]
    end
  end

  defp tile(user, etag \\ nil) do
    conn =
      Plug.Test.conn(:get, "/api/v1/tiles/points/10/548/338.mvt")
      |> assign(:api_user, user)
      |> assign(:api_params, @params)
      |> assign(:api_started, System.monotonic_time())
      |> Map.put(:path_params, %{})

    conn = if etag, do: put_req_header(conn, "if-none-match", etag), else: conn
    PointTilesController.call(conn, :show)
  end
end
