defmodule DawarichWeb.DomainRoutes do
  @moduledoc false

  defmacro family_native_routes do
    quote do
      require DawarichWeb.FamilyFormRoutes
      require DawarichWeb.FamilyNativeRoutes

      pipeline :family_form do
        plug :put_api_tag, "family"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.FamilyDeliveryAdmission
        plug DawarichWeb.FamilyRequestAdmission
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :family_form
        DawarichWeb.FamilyFormRoutes.routes()
      end

      pipeline :native_family_user do
        plug DawarichWeb.RequireUser
      end

      scope "/" do
        pipe_through [:browser, :native_family_user]

        DawarichWeb.FamilyNativeRoutes.http()

        live_session :family_pages,
          session: {DawarichWeb.NativeFamilyAuth, :live_session, []},
          on_mount: {DawarichWeb.NativeFamilyAuth, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          DawarichWeb.FamilyNativeRoutes.pages()
        end
      end
    end
  end

  defmacro native_share_routes do
    quote do
      require DawarichWeb.TrackShareRoutes
      require DawarichWeb.TimelineShareRoutes
      require DawarichWeb.ShareManagementOverrideRoutes
      DawarichWeb.TrackShareRoutes.routes()
      DawarichWeb.TimelineShareRoutes.routes()
      DawarichWeb.ShareManagementOverrideRoutes.routes()
    end
  end
end
