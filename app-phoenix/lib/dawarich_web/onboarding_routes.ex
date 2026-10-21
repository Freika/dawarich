defmodule DawarichWeb.OnboardingRoutes do
  @moduledoc false
  defmacro onboarding_routes do
    quote do
      pipeline :onboarding_qr do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      scope "/" do
        pipe_through :onboarding_qr
        get "/settings/onboarding/qr.svg", DawarichWeb.OnboardingQr, []
      end

      scope "/" do
        pipe_through :standalone_settings

        for method <- [:post, :patch, :put] do
          match method, "/settings/onboarding", DawarichWeb.OnboardingActions, :update
        end

        for method <- [:post, :delete] do
          match method, "/settings/onboarding/demo_data", DawarichWeb.DemoDataActions, :demo_data
        end
      end
    end
  end
end
