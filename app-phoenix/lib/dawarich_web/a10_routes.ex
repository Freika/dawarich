defmodule DawarichWeb.A10Routes do
  @moduledoc false
  defmacro a10_routes do
    quote do
      pipeline :standalone_settings do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.Api.Body
        plug DawarichWeb.RailsHeaders
      end

      pipeline :trial_welcome do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      pipeline :public_home do
        plug DawarichWeb.HostAuthorization
        plug :accepts, ["html"]
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :fetch_query_params
        plug DawarichWeb.TurboVisit
        plug DawarichWeb.RailsAuth
        plug :phoenix_session
        plug :fetch_session
        plug :fetch_live_flash
        plug DawarichWeb.Locale
        plug DawarichWeb.LayoutAssigns
        plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
        plug DawarichWeb.PageEnvelope, :layout
        plug :protect_from_forgery
        plug DawarichWeb.RailsHeaders
      end

      pipeline :trial_resume do
        plug DawarichWeb.HostAuthorization
        plug :accepts, ["html"]
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :fetch_query_params
        plug DawarichWeb.TurboVisit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.TrialResumeHeaders
        plug :phoenix_session
        plug :fetch_session
        plug :fetch_live_flash
        plug DawarichWeb.Locale
        plug DawarichWeb.LayoutAssigns
        plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
        plug DawarichWeb.PageEnvelope, :layout
        plug :protect_from_forgery
        plug DawarichWeb.RailsHeaders
        plug DawarichWeb.RequireUser
        plug DawarichWeb.TrialResumeStatus
      end

      pipeline :background_operator do
        plug DawarichWeb.OperatorRedirect, background: true
      end

      pipeline :admin_page do
        plug DawarichWeb.AuthenticatedPageGate
      end
    end
  end
end
