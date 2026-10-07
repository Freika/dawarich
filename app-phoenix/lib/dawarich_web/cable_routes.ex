defmodule DawarichWeb.CableRoutes do
  @moduledoc false

  defmacro cable_routes do
    quote do
      pipeline :cable do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      scope "/" do
        pipe_through :cable

        get "/cable", DawarichWeb.Cable, :upgrade, metadata: %{slice: :cable}
      end
    end
  end
end
