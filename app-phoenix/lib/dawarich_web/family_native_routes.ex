defmodule DawarichWeb.FamilyNativeRoutes do
  @moduledoc false

  defmacro http do
    quote do
      get "/native/family/invitations/:id/copy", DawarichWeb.FamilyInvitationReveal, :copy,
        metadata: %{native_ui: true}

      get "/native/family/invitations/:id/view", DawarichWeb.FamilyInvitationReveal, :view,
        metadata: %{native_ui: true}

      get "/native/family/upgrade", DawarichWeb.FamilyUpgrade, [], metadata: %{native_ui: true}
    end
  end

  defmacro pages do
    quote do
      live "/family/new", DawarichWeb.FamiliesLive.Form, :new,
        container: {:div, class: "contents"},
        metadata: %{native_ui: true}

      live "/family/edit", DawarichWeb.FamiliesLive.Form, :edit,
        container: {:div, class: "contents"},
        metadata: %{native_ui: true}

      live "/family/invitations", DawarichWeb.FamiliesLive.Invitations, :index,
        container: {:div, class: "contents"},
        metadata: %{native_ui: true}

      live "/family/location_requests/:id", DawarichWeb.FamiliesLive.LocationRequest, :show,
        container: {:div, class: "contents"},
        metadata: %{native_ui: true}
    end
  end
end
