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

  defmacro share_form_routes do
    quote do
      pipeline :share_form do
        plug :put_api_tag, "form"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body, nested_form: "shared_link"
        plug DawarichWeb.RailsAuth
        plug :share_form_admission
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :share_form

        for {base, type, key} <- [
              {"/share_links/live", "live", nil},
              {"/trips/:trip_id/share_link", "trip", "trip_shares"}
            ] do
          metadata = %{rails_key: key, rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}}
          post base, DawarichWeb.ShareManagementForm, {type, :create}, metadata: metadata
          delete base, DawarichWeb.ShareManagementForm, {type, :destroy}, metadata: metadata

          patch base <> "/revoke", DawarichWeb.ShareManagementForm, {type, :revoke},
            metadata: metadata

          post base <> "/regenerate", DawarichWeb.ShareManagementForm, {type, :regenerate},
            metadata: metadata

          post base <> "/regenerate_phrase",
               DawarichWeb.ShareManagementForm,
               {type, :regenerate_phrase},
               metadata: metadata
        end

        patch "/share_links/shares/:id/revoke",
              DawarichWeb.ShareManagementForm,
              {"shared", :revoke},
              metadata: %{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}}
      end

      defp share_form_admission(conn, opts),
        do: DawarichWeb.ShareManagementForm.admit(conn, opts)
    end
  end

  defmacro share_page_routes do
    quote do
      scope "/" do
        pipe_through :rails_frame

        get "/share_links/hub", DawarichWeb.ShareManagementPage, :hub,
          metadata: %{rails_gate: {DawarichWeb.ShareManagementGate, :native?}}

        get "/share_links/live/new", DawarichWeb.ShareManagementPage, :live,
          metadata: %{rails_gate: {DawarichWeb.ShareManagementGate, :native?}}

        get "/trips/:trip_id/share_link/new", DawarichWeb.ShareManagementPage, :trip,
          metadata: %{
            rails_key: "trip_shares",
            rails_gate: {DawarichWeb.ShareManagementGate, :native?}
          }
      end
    end
  end

  defmacro family_invitation_routes do
    quote do
      scope "/" do
        pipe_through :sharing

        get "/invitations/:token", DawarichWeb.FamilyInvitationPage, :show,
          metadata: %{rails_gate: {DawarichWeb.FamilyInvitationPage, :native?}}

        get "/family/invitations/:token", DawarichWeb.FamilyInvitationPage, :show,
          metadata: %{rails_gate: {DawarichWeb.FamilyInvitationPage, :native?}}
      end
    end
  end

  defmacro family_data_routes do
    quote do
      scope "/" do
        pipe_through :family_data

        get "/family/locations.json", DawarichWeb.FamilyLocations, :show,
          metadata: %{rails_gate: {DawarichWeb.FamilyLocations, :native?}}
      end
    end
  end

  defmacro family_page_routes do
    quote do
      live "/family", DawarichWeb.FamiliesLive.Show, :show,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.FamilyGate, :show?}}

      live "/family/new", DawarichWeb.FamiliesLive.Form, :new,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.FamilyGate, :new?}}

      live "/family/edit", DawarichWeb.FamiliesLive.Form, :edit,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.FamilyGate, :edit?}}

      live "/family/invitations", DawarichWeb.FamiliesLive.Invitations, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.FamilyGate, :invitations?}}

      live "/family/location_requests/:id", DawarichWeb.FamiliesLive.LocationRequest, :show,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.FamilyGate, :request?}}
    end
  end
end
