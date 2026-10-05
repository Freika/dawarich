defmodule DawarichWeb.UserDataRoutes do
  @moduledoc false
  defmacro user_data_routes do
    quote do
      pipeline :user_data_export do
        plug :put_api_tag, "user_data"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :fetch_query_params
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.Locale
        plug DawarichWeb.RailsHeaders
        plug DawarichWeb.RequireUser
      end

      pipeline :user_data_import do
        plug :put_api_tag, "user_data"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.RailsForm
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :user_data_export

        get "/settings/users/export", DawarichWeb.UserDataController, :export,
          metadata: %{rails_key: "user_data", rails_gate: {DawarichWeb.UserDataGate, :native?}}
      end

      scope "/" do
        pipe_through :user_data_import

        post "/settings/users/import", DawarichWeb.UserDataController, :import,
          metadata: %{rails_key: "user_data", rails_gate: {DawarichWeb.UserDataGate, :native?}}
      end
    end
  end
end
