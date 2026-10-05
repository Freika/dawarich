defmodule DawarichWeb.Api.VisitsEndpointTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false

  @moduletag api_public_only: true
  @moduletag api_now: ~U[2026-10-03 12:00:00.000000Z]
  @moduletag :capture_log
  @key "a4rest-visits-endpoint"
  @stamp ~N[2026-09-01 12:00:00.000000]

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(visits places))
    rows("DELETE FROM instance_settings")
    user!(%{id: 953_001, api_key: @key, status: 0, settings: %{"timezone" => "UTC"}})

    ScratchRepo.insert_all("users", [
      %{
        id: 953_001,
        email: "a4rest-endpoint@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    :ok
  end

  test "visit collection POST literals preserve exact action and slice tuples" do
    for {path, action} <- [{"merge", :merge}, {"bulk_update", :bulk_update}, {"batch", :batch}] do
      route =
        Phoenix.Router.route_info(
          DawarichWeb.Router,
          "POST",
          "/api/v1/visits/#{path}",
          "localhost"
        )

      assert {route.plug, route.plug_opts, route.slice} ==
               {DawarichWeb.Api.VisitsController, action, :api_visits}
    end
  end

  test "visit writes enforce auth and replay unsupported inputs before effects", ctx do
    assert {401, _, ""} =
             submit(ctx, "POST", "/api/v1/visits", %{"visit" => attrs()}, false)
             |> read_response()

    assert rows("SELECT id FROM visits") == []

    assert {200, _, body} =
             submit(ctx, "POST", "/api/v1/visits", %{"visit" => attrs()}) |> read_response()

    id = Jason.decode!(body)["id"]
    assert rows("SELECT status FROM visits WHERE id=$1", [id]) == [[1]]
    before = rows("SELECT row_to_json(v)::text FROM visits v")
    effects = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

    for {slices, payload} <- [
          {"", %{"visit" => Map.put(attrs(), "name", %{"nested" => "shape"})}},
          {"api_visits", %{"visit" => attrs()}}
        ] do
      System.put_env("DAWARICH_RAILS_SLICES", slices)
      client = submit(ctx, "POST", "/api/v1/visits", payload)
      puma = accept(ctx.upstream)
      {head, rest} = read_head(puma)
      encoded = Jason.encode!(payload)
      assert request_line(head) == "POST /api/v1/visits HTTP/1.1"
      assert read_at_least(puma, rest, byte_size(encoded)) == encoded
      reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
      assert {200, _, "rails"} = read_response(client)
      assert rows("SELECT row_to_json(v)::text FROM visits v") == before
      assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == effects
    end
  end

  test "visit reverse effects enqueue exact handler payloads", ctx do
    ScratchRepo.insert_all("instance_settings", [
      %{
        key: "photon_api_host",
        value: "synthetic.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    assert {200, _, body} =
             submit(ctx, "POST", "/api/v1/visits", %{
               "visit" => Map.put(attrs(), "status", "suggested")
             })
             |> read_response()

    id = Jason.decode!(body)["id"]
    [[place]] = rows("SELECT place_id FROM visits WHERE id=$1", [id])
    assert {204, _, ""} = submit(ctx, "DELETE", "/api/v1/visits/#{id}", nil) |> read_response()

    assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == [
             [
               "visit_months_changed",
               %{"user_id" => 953_001, "started_at" => ["2026-09-01T12:00:00.000000Z"]}
             ],
             ["place_name_fetch", %{"user_id" => 953_001, "place_id" => place}],
             ["places_delete_if_orphan", %{"user_id" => 953_001, "place_ids" => [place]}],
             [
               "visit_months_changed",
               %{"user_id" => 953_001, "started_at" => ["2026-09-01T12:00:00.000000Z"]}
             ]
           ]
  end

  defp attrs,
    do: %{
      "name" => "Synthetic",
      "latitude" => 52.52,
      "longitude" => 13.405,
      "started_at" => "2026-09-01T12:00:00Z",
      "ended_at" => "2026-09-01T13:00:00Z"
    }

  defp submit(ctx, method, target, payload, auth? \\ true) do
    client = connect(ctx.port)
    body = if payload, do: Jason.encode!(payload), else: ""
    auth = if auth?, do: "Authorization: Bearer #{@key}\r\n", else: ""

    send_raw(client, [
      "#{method} #{target} HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\n#{auth}Content-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\n\r\n",
      body
    ])

    client
  end
end
