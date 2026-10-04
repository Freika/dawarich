defmodule DawarichWeb.AccountLive.Edit do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.AccountParts
  import DawarichWeb.ApiKeyParts, only: [api_key: 1]

  alias Dawarich.{Entitlements, SubscriptionToken, UserSettings, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  def page(
        user,
        _params,
        %{
          locale: locale,
          now: now,
          self_hosted: _self_hosted,
          base_url: base_url
        } = context
      ) do
    trial = user.status == 2
    source_none = user.subscription_source in [nil, 0]

    %{
      page_title: t(locale, "devise.registrations.edit.account", %{}),
      rails_js: true,
      account_errors: Map.get(context, :account_errors, []),
      account_email: Map.get(context, :account_email),
      oauth: provider_name(locale, user.provider),
      trial: trial,
      trial_at:
        trial && user.active_until &&
          UserTimeZone.local(UserSettings.get(user), DateTime.to_naive(user.active_until)),
      auto_converting: trial and Entitlements.future?(user.active_until, now) and not source_none,
      legacy_trial: trial and source_none,
      subscription: subscription(user, now),
      points: user.points_count || 0,
      upload_url: base_url <> "/rails/active_storage/direct_uploads"
    }
  end

  defp subscription(%{status: 3}, _now),
    do: "your_signup_isn_t_complete_yet_finish_setting_up_your"

  defp subscription(%{status: 1, active_until: until}, now) do
    if Entitlements.future?(until, now),
      do: "change_plan_update_your_payment_method_or_cancel_your_subscription",
      else: "manage_your_subscription_change_plan_or_update_billing_on_manager"
  end

  defp subscription(_user, _now),
    do: "manage_your_subscription_change_plan_or_update_billing_on_manager"

  defp provider_name(locale, provider) do
    cond do
      not Ruby.present?(provider) -> nil
      provider == "google_oauth2" -> t(locale, "oauth_providers.google", %{})
      provider == "apple" -> t(locale, "oauth_providers.apple", %{})
      provider == "openid_connect" -> System.get_env("OIDC_PROVIDER_NAME", "Openid Connect")
      provider == "github" -> "GitHub"
      true -> Regex.replace(~r/(?:^|_)(.)/, provider, fn _, c -> String.upcase(c) end)
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :manager,
        if(assigns.trial or not assigns.self_hosted,
          do: SubscriptionToken.url(assigns.current_user, assigns.now)
        )
      )

    ~H"""
    <div class="w-full min-w-0 my-5">
      <div class="mx-auto w-full max-w-7xl space-y-6">
        <div>
          <h1 class="text-3xl font-bold sm:text-4xl">
            {t(@locale, "devise.registrations.edit.account_settings", %{})}
          </h1>
        </div>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,24rem)_minmax(0,1fr)] lg:items-start">
          <div class="order-1 space-y-6 lg:sticky lg:top-6">
            <.profile
              locale={@locale}
              user={@current_user}
              errors={@account_errors}
              submitted_email={@account_email}
              oauth={@oauth}
              rails_csrf_token={@rails_csrf_token}
            />
            <.import_dialog
              locale={@locale}
              upload_url={@upload_url}
              legacy_trial={@legacy_trial}
              rails_csrf_token={@rails_csrf_token}
            />
          </div>

          <div class="order-2 space-y-6">
            <.plan_cards
              locale={@locale}
              self_hosted={@self_hosted}
              trial={@trial}
              trial_at={@trial_at}
              auto_converting={@auto_converting}
              manager={@manager}
              subscription={@subscription}
              points={@points}
            />

            <div class="card bg-base-100 shadow-xl">
              <div class="card-body p-5 sm:p-6">
                <div class="max-w-3xl">
                  <h2 class="card-title text-2xl">
                    {t(@locale, "devise.registrations.edit.api_access", %{})}
                  </h2>
                  <p class="mt-1 text-sm text-base-content/70">
                    {t(
                      @locale,
                      "devise.registrations.edit.use_your_api_key_for_clients_imports_and_external_integrations",
                      %{}
                    )}
                  </p>
                </div>
                <.api_key locale={@locale} user={@current_user} base_url={@base_url} />
              </div>
            </div>

            <.data_tools
              locale={@locale}
              user={@current_user}
              self_hosted={@self_hosted}
              oauth={@oauth}
              rails_csrf_token={@rails_csrf_token}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
