defmodule DawarichWeb.RouteConstraints do
  @moduledoc false
  @constraints %{
    "/api/v1/tiles/points/:z/:x/:y" => %{"y" => ~r/\A[^\/]+\.mvt\z/},
    "/api/v1/tiles/tracks/:z/:x/:y" => %{"y" => ~r/\A[^\/]+\.mvt\z/},
    "/family/location_requests/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/route_videos/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/visits/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/settings/users/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/settings/users/:id/edit" => %{"id" => ~r/\A\d{1,18}\z/},
    "/tracks/:track_id/segments" => %{"track_id" => ~r/\A\d{1,18}\z/},
    "/points/:id/address" => %{"id" => ~r/\A\d{1,18}\z/},
    "/map/timeline_feeds/:id/track_info" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id/edit" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id/recalculate" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id/export" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:trip_id/notes" => %{"trip_id" => ~r/\A\d{1,18}\z/},
    "/trips/:trip_id/notes/:id" => %{"trip_id" => ~r/\A\d{1,18}\z/, "id" => ~r/\A\d{1,18}\z/},
    "/places/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/tracks/:track_id/segments/:id" => %{
      "track_id" => ~r/\A[1-9]\d{0,17}\z/,
      "id" => ~r/\A[1-9]\d{0,17}\z/
    },
    "/stats/:year" => %{"year" => ~r/\A\d{4}\z/},
    "/stats/:year/:month" => %{"year" => ~r/\A\d{4}\z/, "month" => ~r/\A(0?[1-9]|1[0-2])\z/},
    "/digests/:year" => %{"year" => ~r/\A\d{4}\z/},
    "/api/v1/digests/:year" => %{"year" => ~r/\A\d{4}\z/}
  }

  def valid?(%{route: route, path_params: params} = info) do
    info[:native_page] == true or :native_m6_browser in Map.get(info, :pipe_through, []) or
      Enum.all?(Map.get(@constraints, route, %{}), fn {name, pattern} ->
        Regex.match?(pattern, params[name])
      end)
  end
end
