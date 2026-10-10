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

        get "/settings/mobile", MobileSettingsController, :show,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        get "/areas", AreasController, :index,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        post "/areas", AreasController, :create,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        get "/areas/:id", AreasController, :show,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        patch "/areas/:id", AreasController, :update,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        put "/areas/:id", AreasController, :update,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        delete "/areas/:id", AreasController, :destroy,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :standalone_api_active

        post "/recalculations", RecalculationsController, :create,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        patch "/settings/mobile", MobileSettingsController, :update,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        patch "/settings", SettingsController, :update,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        get "/demo_data", DemoDataController, :show,
          metadata: %{
            slice: :api_foundation,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        post "/demo_data", DemoDataController, :create,
          metadata: %{
            slice: :api_foundation,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        delete "/demo_data", DemoDataController, :destroy,
          metadata: %{
            slice: :api_foundation,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        post "/digests", DigestWritesController, :create,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }

        delete "/digests/:year", DigestWritesController, :destroy,
          metadata: %{
            slice: :api_standalone,
            rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
          }
      end
    end
  end
end
