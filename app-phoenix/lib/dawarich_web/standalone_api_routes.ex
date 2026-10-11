defmodule DawarichWeb.StandaloneApiRoutes do
  @moduledoc false

  defmacro standalone_api_routes do
    quote do
      pipeline :standalone_api do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      pipeline :standalone_api_active do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: true
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :standalone_api

        get "/settings/mobile", MobileSettingsController, :show, metadata: %{head: false}

        get "/areas", AreasController, :index, metadata: %{head: false}

        post "/areas", AreasController, :create, metadata: %{head: false}

        get "/areas/:id", AreasController, :show, metadata: %{head: false}

        patch "/areas/:id", AreasController, :update, metadata: %{head: false}

        put "/areas/:id", AreasController, :update, metadata: %{head: false}

        delete "/areas/:id", AreasController, :destroy, metadata: %{head: false}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :standalone_api_active

        post "/recalculations", RecalculationsController, :create, metadata: %{head: false}

        patch "/settings/mobile", MobileSettingsController, :update, metadata: %{head: false}

        patch "/settings", SettingsController, :update, metadata: %{head: false}

        get "/demo_data", DemoDataController, :show

        post "/demo_data", DemoDataController, :create

        delete "/demo_data", DemoDataController, :destroy

        post "/digests", DigestWritesController, :create, metadata: %{head: false}

        delete "/digests/:year", DigestWritesController, :destroy, metadata: %{head: false}
      end
    end
  end
end
