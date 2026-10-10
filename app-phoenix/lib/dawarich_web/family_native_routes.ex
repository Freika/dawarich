defmodule DawarichWeb.FamilyNativeRoutes do
  @moduledoc false

  defmacro http do
    quote do
      get "/native/family/invitations/:id/copy", DawarichWeb.FamilyInvitationReveal, :copy
      get "/native/family/invitations/:id/view", DawarichWeb.FamilyInvitationReveal, :view
      get "/native/family/upgrade", DawarichWeb.FamilyUpgrade, []
    end
  end

  defmacro pages do
    quote do
      live "/family", DawarichWeb.FamiliesLive.Show, :show, container: {:div, class: "contents"}

      live "/family/new", DawarichWeb.FamiliesLive.Form, :new,
        container: {:div, class: "contents"}

      live "/family/edit", DawarichWeb.FamiliesLive.Form, :edit,
        container: {:div, class: "contents"}

      live "/family/invitations", DawarichWeb.FamiliesLive.Invitations, :index,
        container: {:div, class: "contents"}

      live "/family/location_requests/:id", DawarichWeb.FamiliesLive.LocationRequest, :show,
        container: {:div, class: "contents"}
    end
  end
end
