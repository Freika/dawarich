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

      pipeline :test_email do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      scope "/" do
        pipe_through :test_email

        post "/settings/general/test_email", DawarichWeb.TestEmail, [],
          metadata: %{rails_key: "test_email", rails_gate: {DawarichWeb.TestEmailGate, :owned?}}
      end

      pipeline :admin_writes do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
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
        plug :protect_from_forgery
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :admin_writes

        post "/settings/users/update_registration_settings",
             DawarichWeb.AdminWrites.Settings,
             [action: :registration],
             metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :registration?}}

        patch "/settings/users/update_registration_settings",
              DawarichWeb.AdminWrites.Settings,
              [action: :registration],
              metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :registration?}}

        post "/settings/users", DawarichWeb.AdminWrites.Users, [action: :create],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :create?}}

        post "/settings/users/:id", DawarichWeb.AdminWrites.Users, [action: :update],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :update?}}

        patch "/settings/users/:id", DawarichWeb.AdminWrites.Users, [action: :update],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :update?}}

        put "/settings/users/:id", DawarichWeb.AdminWrites.Users, [action: :update],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :update?}}

        post "/settings/users/:id/regenerate_api_key",
             DawarichWeb.AdminWrites.Users,
             [action: :rotate],
             metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :rotate?}}

        post "/settings/users/:id/send_password_reset",
             DawarichWeb.AdminWrites.Users,
             [action: :reset],
             metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :reset?}}

        post "/admin/settings", DawarichWeb.AdminWrites.Settings, [action: :instance],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :instance?}}

        patch "/admin/settings", DawarichWeb.AdminWrites.Settings, [action: :instance],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :instance?}}

        put "/admin/settings", DawarichWeb.AdminWrites.Settings, [action: :instance],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :instance?}}

        patch "/settings/background_jobs",
              DawarichWeb.AdminWrites.Settings,
              [action: :background],
              metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :background?}}
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

      scope "/" do
        pipe_through [:browser, :rails_user, :admin_page]

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
      end

      scope "/" do
        pipe_through [:browser, :rails_user, :background_operator]

        live_session :background_read,
          session: {DawarichWeb.OperatorRedirect, :live_session, []},
          on_mount: {DawarichWeb.AdminLiveAuth, :background},
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/settings/background_jobs", DawarichWeb.SettingsLive.BackgroundJobs, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AdminGate, :background_route?}}
        end
      end
    end
  end
end
