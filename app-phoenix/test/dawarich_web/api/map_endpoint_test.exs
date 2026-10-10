defmodule DawarichWeb.Api.MapEndpointTest do
  use Dawarich.ApiEndpointCase

  @moduletag :capture_log

  @key "phoenix-a4map-key-endpoint"
  @target "/api/v1/points?end_at=1790856000"

  test "a fresh points request answers 304 without fetching or serializing a row", %{
    port: port,
    upstream: upstream
  } do
    id = user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})

    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) " <>
        "VALUES ($1, 1735689600, 'SRID=4326;POINT(13 52)', now(), now())",
      [id]
    )

    headers = [{"Authorization", "Bearer #{@key}"}, {"Accept", "application/json"}]
    assert {200, first, _body} = port |> request(@target, headers) |> read_response()
    [etag] = values(first, "etag")
    handler = "map-api-304-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _event, _measurements, meta, _config -> send(test_pid, {:sql, meta.query}) end,
      nil
    )

    try do
      assert {304, _headers, ""} =
               port |> request(@target, headers ++ [{"If-None-Match", etag}]) |> read_response()
    after
      :telemetry.detach(handler)
    end

    queries = drain([])
    assert Enum.any?(queries, &String.contains?(&1, "MAX(p.updated_at)"))
    refute Enum.any?(queries, &String.contains?(&1, "ST_Y"))
    no_upstream!(upstream)
  end

  defp drain(acc) do
    receive do
      {:sql, sql} -> drain([sql | acc])
    after
      0 -> acc
    end
  end
end
