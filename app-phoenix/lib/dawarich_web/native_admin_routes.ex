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
        end
      end

      scope "/" do
        pipe_through [:browser, :rails_user, :background_operator]

        live_session :native_background,
          session: {DawarichWeb.OperatorRedirect, :live_session, []},
          on_mount: {DawarichWeb.AdminLiveAuth, :native_background},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
        end
      end
    end
  end
end
