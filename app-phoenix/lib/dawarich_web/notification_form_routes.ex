defmodule DawarichWeb.NotificationFormRoutes do
  @moduledoc false
  defmacro notification_form_routes do
    quote do
      scope "/" do
        pipe_through :standalone_settings

        post "/notifications/mark_as_read", DawarichWeb.NotificationActions, :mark_as_read,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}

        post "/notifications/destroy_all", DawarichWeb.NotificationActions, :destroy_all,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}

        delete "/notifications/:id", DawarichWeb.NotificationActions, :destroy,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}

        post "/notifications/:id", DawarichWeb.NotificationActions, :destroy,
          metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}
      end
    end
  end
end
