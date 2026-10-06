defmodule DawarichWeb.SettingsFormRoutes do
  @moduledoc false
  defmacro settings_form_routes do
    quote do
      scope "/" do
        pipe_through :standalone_settings

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
