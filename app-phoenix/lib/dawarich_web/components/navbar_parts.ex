defmodule DawarichWeb.NavbarParts do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.Icon

  attr :locale, :string, required: true

  def help_links(assigns) do
    ~H"""
    <li>
      <p>
        {t(@locale, "shared.navbar.help_links.need_help_ping_us", %{})}
        <Icon.icon name="arrow-big-down" class="size-6" />
      </p>
    </li>
    <li>
      <a target="_blank" rel="noopener noreferrer" href="https://x.com/freymakesstuff">{t(
        @locale,
        "shared.navbar.help_links.x_twitter",
        %{}
      )}</a>
    </li>
    <li>
      <a target="_blank" rel="noopener noreferrer" href="https://mastodon.social/@dawarich">{t(
        @locale,
        "shared.navbar.help_links.mastodon",
        %{}
      )}</a>
    </li>
    <li><a href="mailto:hi@dawarich.app">{t(@locale, "shared.navbar.help_links.email", %{})}</a></li>
    <li>
      <a target="_blank" rel="noopener noreferrer" href="https://discourse.dawarich.app">{t(
        @locale,
        "shared.navbar.help_links.forum",
        %{}
      )}</a>
    </li>
    <li>
      <a target="_blank" rel="noopener noreferrer" href="https://discord.gg/pHsBjpt5J8">{t(
        @locale,
        "shared.navbar.help_links.discord",
        %{}
      )}</a>
    </li>
    """
  end

  attr :locale, :string, required: true
  attr :theme, :string, default: nil
  attr :class, :string, default: "btn btn-ghost"
  attr :label, :boolean, default: false
  attr :native, :boolean, default: false

  def theme_toggle(assigns) do
    assigns = assign(assigns, :target, if(assigns.theme == "light", do: "dark", else: "light"))

    ~H"""
    <a data-turbo={!@native && "false"} class={@class} href={"/settings/theme?theme=#{@target}"}>
      <Icon.icon name={if @target == "dark", do: "moon", else: "sun"} class="size-6" />
      <span :if={@label}>{t(@locale, "shared.navbar.theme_toggle.#{@target}_mode", %{})}</span>
    </a>
    """
  end

  attr :locale, :string, required: true
  attr :sharing, :boolean, required: true
  attr :native, :boolean, default: false

  def family_indicator(%{native: true} = assigns) do
    ~H"""
    <span
      id="family-navbar-indicator"
      class={"tooltip tooltip-bottom inline-block w-2 h-2 #{if @sharing, do: "bg-green-500 animate-pulse", else: "bg-gray-400"} rounded-full"}
      data-tip={
        t(
          @locale,
          "families.navbar_indicator.#{if @sharing, do: "location_shared", else: "location_not_shared"}",
          %{}
        )
      }
    ></span>
    """
  end

  def family_indicator(assigns) do
    ~H"""
    <turbo-frame id="family-navbar-indicator">
      <div
        data-controller="family-navbar-indicator"
        data-family-navbar-indicator-enabled-value={to_string(@sharing)}
      >
        <div
          data-family-navbar-indicator-target="indicator"
          class={"tooltip tooltip-bottom w-2 h-2 #{if @sharing, do: "bg-green-500 animate-pulse", else: "bg-gray-400"} rounded-full"}
          data-tip={
            t(
              @locale,
              "families.navbar_indicator.#{if @sharing, do: "location_shared", else: "location_not_shared"}",
              %{}
            )
          }
        >
        </div>
      </div>
    </turbo-frame>
    """
  end

  attr :locale, :string, required: true
  attr :version, :map, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :native, :boolean, default: false

  def version_indicator(assigns) do
    ~H"""
    <div id="version-indicator" class="relative inline-flex items-center">
      <div class={"badge mx-4 #{if @version.update, do: "badge-outline"}"}>
        <a
          href="https://github.com/Freika/dawarich/releases/latest"
          target="_blank"
          class="inline-flex items-center"
        >
          <%= if @version.update do %>
            <span
              class="tooltip tooltip-bottom"
              data-tip={
                t(
                  @locale,
                  "shared.navbar.version_indicator.new_version_available_check_out_github_releases",
                  %{}
                )
              }
            >
              <span class="hidden sm:inline">{@version.number}{t(
                @locale,
                "shared.navbar.version_indicator.nbsp",
                %{}
              )}</span>
            </span>
          <% else %>
            <span class="hidden sm:inline">{@version.number}</span>
          <% end %>
        </a>
      </div>
      <div
        :if={@version.state == :widget}
        id="chgtool-mount"
        class="inline-flex items-center"
        data-controller={!@native && "changelog-widget"}
        data-changelog-widget-src-value={@version.widget_src}
        data-changelog-widget-slug-value={@version.slug}
        data-changelog-widget-version-value={@version.number}
        phx-hook="ChangelogWidget"
        phx-update="ignore"
      >
      </div>
      <div :if={@version.state == :prompt} class="dropdown dropdown-end dropdown-open">
        <div class="card card-compact w-72 bg-base-100 shadow-lg border border-base-300 absolute right-0 mt-2 z-[60]">
          <div class="card-body">
            <h3 class="font-semibold text-sm">
              {t(@locale, "shared.navbar.changelog_prompt.stay_up_to_date", %{})}
            </h3>
            <p class="text-xs opacity-80">
              {t(
                @locale,
                "shared.navbar.changelog_prompt.get_a_what_s_new_notice_when_a_new_dawarich",
                %{}
              )} {@version.widget_host}{t(
                @locale,
                "shared.navbar.changelog_prompt.like_any_web_request_that_host_sees_your_ip_address",
                %{}
              )}
            </p>
            <div class="card-actions justify-end mt-1">
              <.consent_form
                :for={
                  {decision, class, label} <- [
                    {"declined", "btn btn-ghost btn-xs", "no_thanks"},
                    {"granted", "btn btn-primary btn-xs", "yes_notify_me"}
                  ]
                }
                decision={decision}
                class={class}
                label={t(@locale, "shared.navbar.changelog_prompt.#{label}", %{})}
                rails_csrf_token={@rails_csrf_token}
                native={@native}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :decision, :string, required: true
  attr :class, :string, required: true
  attr :label, :string, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :native, :boolean, default: false

  def consent_form(assigns) do
    ~H"""
    <form
      data-turbo-stream={!@native && "true"}
      class="button_to"
      method="post"
      action="/settings/changelog_consent"
      phx-submit="changelog_consent"
    >
      <input type="hidden" name="_method" value="patch" /><button class={@class} type="submit">{@label}</button><input
        :if={@rails_csrf_token}
        type="hidden"
        name="authenticity_token"
        value={@rails_csrf_token}
      /><input type="hidden" name="decision" value={@decision} />
    </form>
    """
  end
end
