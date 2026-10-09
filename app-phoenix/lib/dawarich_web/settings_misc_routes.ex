defmodule DawarichWeb.SettingsMiscRoutes do
  @moduledoc false
  defmacro settings_misc_routes do
    quote do
      scope "/" do
        pipe_through :standalone_settings

        get "/settings/theme", DawarichWeb.SettingsMiscActions, :theme,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}

        patch "/settings/changelog_consent", DawarichWeb.SettingsMiscActions, :changelog_consent,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}

        post "/settings/changelog_consent", DawarichWeb.SettingsMiscActions, :changelog_consent,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}
      end
    end
  end
end
