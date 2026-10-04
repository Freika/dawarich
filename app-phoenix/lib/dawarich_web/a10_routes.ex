defmodule DawarichWeb.A10Routes do
  @moduledoc false
  defmacro a10_routes do
    quote do
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
        plug :protect_from_forgery
        plug DawarichWeb.RailsHeaders
        plug DawarichWeb.RequireUser
        plug DawarichWeb.TrialResumeStatus
      end

      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :admin_reads,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: {DawarichWeb.AdminLiveAuth, :admin},
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/admin/settings", DawarichWeb.AdminLive.Instance, :show,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :instance?}}

          live "/settings/users", DawarichWeb.SettingsLive.UsersIndex, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :users?}}

          live "/settings/users/:id", DawarichWeb.SettingsLive.UserShow, :show,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :users?}}

          live "/settings/users/:id/edit", DawarichWeb.SettingsLive.UserEdit, :edit,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :users?}}
        end

        live_session :background_read,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: {DawarichWeb.AdminLiveAuth, :background},
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/settings/background_jobs", DawarichWeb.SettingsLive.BackgroundJobs, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :background?}}
        end
      end

      scope "/" do
        pipe_through :rails_frame

        get "/trial/upgrade", DawarichWeb.TrialUpgrade, [],
          metadata: %{rails_gate: {DawarichWeb.TrialGate, :upgrade?}}

        get "/", DawarichWeb.InsightsHome, :index,
          metadata: %{rails_gate: {DawarichWeb.HomeGate, :owned?}}
      end

      scope "/" do
        pipe_through :trial_resume

        live_session :trial_resume,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: DawarichWeb.TrialLiveAuth,
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/trial/resume", DawarichWeb.TrialLive.Resume, :show,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.TrialGate, :resume?}}
        end
      end
    end
  end
end
