defmodule DawarichWeb.NativeAdminRoutes do
  @moduledoc false
  defmacro native_admin_routes do
    quote do
      scope "/" do
        pipe_through [:browser, :rails_user, :admin_page]

        live_session :native_admin,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: {DawarichWeb.AdminLiveAuth, :native_admin},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/admin/settings", DawarichWeb.AdminLive.Instance, :show,
            container: {:div, class: "contents"}

          live "/settings/users/:id/edit", DawarichWeb.SettingsLive.UserEdit, :edit,
            container: {:div, class: "contents"}

          live "/settings/users/:id", DawarichWeb.SettingsLive.UserShow, :show,
            container: {:div, class: "contents"}

          live "/settings/users", DawarichWeb.SettingsLive.UsersIndex, :index,
            container: {:div, class: "contents"}
        end
      end

      scope "/" do
        pipe_through [:browser, :rails_user, :background_operator]

        live_session :native_background,
          session: {DawarichWeb.OperatorRedirect, :live_session, []},
          on_mount: {DawarichWeb.AdminLiveAuth, :native_background},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/settings/background_jobs", DawarichWeb.SettingsLive.BackgroundJobs, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :background_route?}}
        end
      end
    end
  end
end
