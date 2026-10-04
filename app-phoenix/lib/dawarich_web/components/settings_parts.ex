defmodule DawarichWeb.SettingsParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  attr :locale, :string, required: true
  attr :active, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :admin, :boolean, required: true
  attr :two_factor, :boolean, required: true

  def navigation(assigns) do
    ~H"""
    <div
      id="settings-navigation"
      phx-hook="RailsStimulus"
      class="mb-6 overflow-x-auto pb-1"
      data-controller="scroll-into-view"
    >
      <div class="tabs tabs-boxed inline-flex min-w-max flex-nowrap">
        <a role="tab" class={tab(@active, "general")} href="/settings/general">{t(
          @locale,
          "settings.navigation.general",
          %{}
        )}</a>
        <a role="tab" class={tab(@active, "integrations")} href="/settings/integrations">{t(
          @locale,
          "settings.navigation.integrations",
          %{}
        )}</a>
        <a role="tab" class={tab(@active, "visits")} href="/settings/visits">{t(
          @locale,
          "settings.navigation.visits",
          %{}
        )}</a>
        <a :if={@two_factor} role="tab" class={tab(@active, "two_factor")} href="/settings/two_factor">{t(
          @locale,
          "settings.navigation.two_factor_authentication",
          %{}
        )}</a>
        <%= if @self_hosted do %>
          <%= if @admin do %>
            <a role="tab" class={tab(@active, "users")} href="/settings/users">{t(
              @locale,
              "settings.navigation.users",
              %{}
            )}</a>
            <a role="tab" class={tab(@active, "instance")} href="/admin/settings">{t(
              @locale,
              "settings.navigation.instance",
              %{}
            )}</a>
          <% end %>
          <a role="tab" class={tab(@active, "background_jobs")} href="/settings/background_jobs">{t(
            @locale,
            "settings.navigation.background_jobs",
            %{}
          )}</a>
        <% end %>
      </div>
    </div>
    """
  end

  defp tab(active, active), do: "tab tab-lg tab-active"
  defp tab(_active, _tab), do: "tab tab-lg"

  def smtp_configured?, do: Ruby.present?(System.get_env("SMTP_SERVER"))

  def two_factor_available?,
    do:
      Enum.all?(
        ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT),
        &Ruby.present?(System.get_env(&1))
      )

  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true

  def toggle(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-4">
        <input name={@name} type="hidden" value="0" /><input
          class="toggle toggle-primary"
          type="checkbox"
          value="1"
          checked={@checked && "checked"}
          name={@name}
          id={@name}
          phx-update="ignore"
        />
        <div>
          <span class="label-text font-medium">{@label}</span>
          <p class="text-sm text-base-content/70 mt-1">
            {@hint}
          </p>
        </div>
      </label>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :supporter, :boolean, required: true
  attr :platform, :string, default: nil
  attr :rails_csrf_token, :string, default: nil

  def supporter_card(assigns), do: DawarichWeb.Components.SupporterCard.card(assigns)

  attr :locale, :string, required: true
  attr :granted, :boolean, required: true
  attr :rails_csrf_token, :string, default: nil

  def consent_card(assigns) do
    assigns = assign(assigns, :host, Dawarich.Navbar.changelog_host())

    ~H"""
    <div id="changelog-consent-setting" class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="text-2xl font-bold mb-4 flex items-center">
          <.icon name="bell" class="text-primary mr-2" /> {t(
            @locale,
            "settings.general.changelog_consent.what_s_new_notices",
            %{}
          )}
        </h2>
        <div class="bg-base-100 p-5 rounded-lg shadow-sm space-y-4">
          <%= if @granted do %>
            <p class="text-sm text-base-content/70">
              {t(
                @locale,
                "settings.general.changelog_consent.a_what_s_new_notice_is_shown_when_a_new",
                %{}
              )}
              {@host}{t(
                @locale,
                "settings.general.changelog_consent.which_like_any_web_request_sees_your_ip_address_browser",
                %{}
              )}
            </p>
            <DawarichWeb.NavbarParts.consent_form
              decision="declined"
              class="btn btn-ghost btn-sm"
              label={t(@locale, "settings.general.changelog_consent.turn_off_notices", %{})}
              rails_csrf_token={@rails_csrf_token}
            />
          <% else %>
            <p class="text-sm text-base-content/70">
              {t(
                @locale,
                "settings.general.changelog_consent.get_a_what_s_new_notice_when_a_new_dawarich",
                %{}
              )}
              {@host}{t(
                @locale,
                "settings.general.changelog_consent.which_like_any_web_request_sees_your_ip_address_browser",
                %{}
              )}
            </p>
            <DawarichWeb.NavbarParts.consent_form
              decision="granted"
              class="btn btn-primary btn-sm"
              label={t(@locale, "settings.general.changelog_consent.turn_on_notices", %{})}
              rails_csrf_token={@rails_csrf_token}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
