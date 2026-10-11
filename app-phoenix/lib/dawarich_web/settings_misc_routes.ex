defmodule DawarichWeb.SettingsMiscRoutes do
  @moduledoc false
  defmacro settings_misc_routes do
    quote do
      scope "/" do
        pipe_through :standalone_settings

        get "/settings/theme", DawarichWeb.SettingsMiscActions, :theme

        patch "/settings/changelog_consent", DawarichWeb.SettingsMiscActions, :changelog_consent

        post "/settings/changelog_consent", DawarichWeb.SettingsMiscActions, :changelog_consent
      end
    end
  end
end
