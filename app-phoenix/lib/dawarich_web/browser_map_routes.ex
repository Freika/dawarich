defmodule DawarichWeb.BrowserMapRoutes do
  @moduledoc false
  defmacro browser_map_routes do
    quote do
      pipeline :browser_map_read do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :fetch_query_params
        plug DawarichWeb.BrowserMapAuth
      end

      scope "/native/map/data" do
        pipe_through :browser_map_read

        for {path, action} <- [
              {"/points", :points},
              {"/tracks", :tracks},
              {"/tracks/:id", :track},
              {"/tracks/:track_id/points", :track_points},
              {"/settings", :settings},
              {"/bounds", :bounds},
              {"/photos", :photos},
              {"/photos/:id/thumbnail", :thumbnail},
              {"/locations", :locations},
              {"/locations/suggestions", :suggestions},
              {"/places", :places},
              {"/places/search", :place_search},
              {"/places/nearby", :nearby},
              {"/visits", :visits},
              {"/areas", :areas},
              {"/timeline", :timeline},
              {"/hexagons", :hexagons},
              {"/fog", :fog},
              {"/flights", :flights},
              {"/tiles/points/:z/:x/:y", :point_tiles},
              {"/tiles/tracks/:z/:x/:y", :track_tiles}
            ] do
          get path, DawarichWeb.BrowserMapData, action
        end

        for method <- [:post, :put, :patch, :delete, :options] do
          match method, "/*path", DawarichWeb.BrowserMapData, :refused
        end
      end
    end
  end
end
