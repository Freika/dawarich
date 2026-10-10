defmodule DawarichWeb.A9Routes do
  @moduledoc false

  defmacro poster_routes do
    quote do
      pipeline :poster_form do
        plug :put_api_tag, "form"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body, nested_form: "poster"
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.PostersGate
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :poster_form

        post "/posters", DawarichWeb.PostersController, :create,
          metadata: %{rails_gate: {DawarichWeb.PostersGate, :native?}}

        delete "/posters/:id", DawarichWeb.PostersController, :destroy,
          metadata: %{rails_gate: {DawarichWeb.PostersGate, :native?}}
      end
    end
  end

  defmacro share_page_routes do
    quote do
      require DawarichWeb.NativeSharingRoutes
      DawarichWeb.NativeSharingRoutes.pages()
    end
  end

  defmacro family_invitation_routes do
    quote do
      scope "/" do
        pipe_through :sharing

        get "/invitations/:token", DawarichWeb.FamilyInvitationPage, :show,
          metadata: %{native_ui: true}

        get "/family/invitations/:token", DawarichWeb.FamilyInvitationPage, :show,
          metadata: %{native_ui: true}
      end
    end
  end

  defmacro family_data_routes do
    quote do
      scope "/" do
        pipe_through :family_data

        get "/family/locations.json", DawarichWeb.FamilyLocations, :show,
          metadata: %{native_ui: true}
      end
    end
  end
end
