defmodule DawarichWeb.DomainRoutes do
  @moduledoc false

  defmacro family_native_routes do
    quote do
      require DawarichWeb.FamilyFormRoutes

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

      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :family_pages,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: [DawarichWeb.LiveAuth, {DawarichWeb.FamilyGate, :default}],
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          family_page_routes()
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
