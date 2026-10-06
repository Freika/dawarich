defmodule DawarichWeb.A12f2JClosureTest do
  use Dawarich.ApiEndpointCase

  @moduletag :capture_log
  @key "a12f2-j-synthetic-api-key"

  @tag :a12f2_j_activate_b
  test "Merged photos places and search handlers are reachable through the real Endpoint", c do
    for {method, path} <- [
          {"GET", "/api/v1/photos"},
          {"GET", "/api/v1/locations/suggestions"},
          {"GET", "/api/v1/places/nearby"},
          {"GET", "/api/v1/places/search"},
          {"POST", "/api/v1/immich/enrich/scan"},
          {"POST", "/api/v1/immich/enrich"}
        ] do
      assert {401, _, ""} = endpoint(c, method, path), path
    end

    user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})
    assert {200, _, body} = endpoint(c, "GET", "/api/v1/locations/suggestions", bearer())
    assert is_map(Jason.decode!(body))

    for {path, action} <- [
          {"/api/v1/locations", :index_closure},
          {"/api/v1/photos/photo/thumbnail", :thumbnail_closure},
          {"/api/v1/places", {:closure, :index}}
        ] do
      assert route("GET", path).plug_opts == action
    end

    no_upstream!(c.upstream)
  end

  defp bearer, do: [{"Authorization", "Bearer #{@key}"}, {"Accept", "application/json"}]

  defp route(method, path),
    do: Phoenix.Router.route_info(DawarichWeb.Router, method, path, "localhost")

  defp endpoint(c, method, path, headers \\ []) do
    upstream = Task.async(fn -> puma(c.upstream, "unexpected Rails replay") end)

    try do
      c.port |> request(path, headers, method) |> read_response()
    after
      Task.shutdown(upstream, :brutal_kill)
    end
  end
end
