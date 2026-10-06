defmodule DawarichWeb.SettingsFormRoutes do
  @moduledoc false
  defmacro settings_form_routes do
    quote do
      pipeline :settings_forms do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.Api.Body
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :settings_forms

        for method <- [:post, :patch, :put] do
          match method, "/settings/general", DawarichWeb.SettingsActions, :update,
            metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}
        end

        post "/settings/general/verify_supporter", DawarichWeb.SettingsSupporterActions, :verify,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}
      end
    end
  end
end
