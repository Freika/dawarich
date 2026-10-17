defmodule DawarichWeb.PublicMapRoutes do
  @moduledoc false
  defmacro public_map_routes do
    quote do
      pipeline :public_map_read do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      scope "/native/public/maps/:id" do
        pipe_through :public_map_read

        for {path, action} <- [
              {"/metadata", :metadata},
              {"/points", :points},
              {"/route", :route},
              {"/photos", :photos},
              {"/photos/:photo_id/thumbnail", :thumbnail}
            ] do
          get path, DawarichWeb.PublicMapRead, action
        end

        for method <- [:post, :put, :patch, :delete, :options] do
          match method, "/*path", DawarichWeb.PublicMapRead, :refused
        end
      end
    end
  end
end
