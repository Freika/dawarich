defmodule DawarichWeb.DomainRoutes do
  @moduledoc false

  defmacro family_native_routes do
    quote do
      require DawarichWeb.FamilyNativeRoutes

      pipeline :family_acceptance do
        plug :put_api_tag, "family"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :family_acceptance

        post "/family/memberships", DawarichWeb.FamilyInvitationAcceptance, [],
          metadata: %{native_ui: true}

        post "/family/memberships.:format", DawarichWeb.FamilyInvitationAcceptance, [],
          metadata: %{native_ui: true}
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
end
