defmodule DawarichWeb.NavbarEnd do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.NavbarParts, only: [help_links: 1]

  alias Dawarich.SubscriptionToken
  alias DawarichWeb.{Icon, TimeAgo}

  attr :current_user, :any, required: true
  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :now, :any, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :native, :boolean, default: false

  def navbar_end(assigns) do
    ~H"""
    <div class="navbar-end">
      <%= if @current_user do %>
        <div class="flex items-center gap-1 xl:hidden">
          <a
            :if={@data.subscription}
            class={"btn btn-xs #{trial_class(@data.subscription)}"}
            href={upgrade_url(@current_user, @data.subscription, @now)}
          >{compact(@locale, @data.subscription)}</a>
          <a class="btn btn-ghost btn-sm relative" href="/notifications">
            <Icon.icon name="bell" class="size-6" />
            <span
              :if={@data.unread.count > 0}
              class="badge badge-xs badge-primary absolute top-0 right-0"
            >{count(@data.unread.count)}</span>
          </a>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-ghost btn-sm">
              <Icon.icon name="user" class="size-6" />
              <span :if={@data.onboarding} class="indicator-item badge badge-secondary badge-xs"></span>
            </label>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm mt-3 z-[50] p-2 shadow bg-base-100 rounded-box w-52"
            >
              <.account_items
                locale={@locale}
                self_hosted={@self_hosted}
                current_user={@current_user}
                onboarding={@data.onboarding}
                now={@now}
                rails_csrf_token={@rails_csrf_token}
                native={@native}
              />
            </ul>
          </div>
        </div>
        <div class="hidden xl:flex items-center gap-2 flex-nowrap">
          <a
            :if={@data.subscription}
            class="join flex-nowrap"
            href={upgrade_url(@current_user, @data.subscription, @now)}
          >
            <span class={"join-item btn btn-sm #{trial_class(@data.subscription)}"}>
              <.trial_state locale={@locale} subscription={@data.subscription} now={@now} />
            </span><span class="join-item btn btn-sm btn-success">{t(
              @locale,
              if(@data.subscription.pending,
                do: "helpers.application.resume",
                else: "helpers.application.subscribe"
              ),
              %{}
            )}</span>
          </a>
          <ul class="menu menu-horizontal px-1 flex-nowrap">
            <li data-controller={!@native && "notifications"}>
              <details>
                <summary class="relative">
                  <Icon.icon name="bell" class="size-6" />
                  <.badge count={@data.unread.count} />
                </summary>
                <ul class="p-2 bg-base-100 rounded-t-none z-[50] min-w-52" id="notifications-list">
                  <li><a href="/notifications">{t(@locale, "shared.navbar.see_all", %{})}</a></li>
                  <.navbar_item :for={item <- @data.unread.items} item={item} />
                </ul>
              </details>
            </li>
            <li>
              <details>
                <summary><Icon.icon name="message-circle-question-mark" class="size-6" /></summary>
                <ul class="p-2 bg-base-100 rounded-box shadow-md z-[50] w-52">
                  <.help_links locale={@locale} />
                </ul>
              </details>
            </li>
            <li>
              <details>
                <summary>
                  <span class="inline"><Icon.icon name="user" class="size-6" /></span>
                  <span :if={@data.onboarding} class="indicator-item badge badge-secondary badge-xs"></span>
                  <span
                    :if={@current_user.admin}
                    class="tooltip tooltip-left"
                    data-tip={t(@locale, "shared.navbar.you_re_an_admin_harry", %{})}
                  ><Icon.icon name="star" class="size-6" /></span>
                  <span
                    :if={@data.supporter}
                    class="tooltip tooltip-left"
                    data-tip={t(@locale, "shared.navbar.dawarich_supporter", %{})}
                  >
                    <span class="text-sky-400 inline-block animate-[supporter-rainbow-glow_8s_linear_infinite]"><Icon.icon
                      name="gem"
                      class="size-6"
                    /></span>
                  </span>
                </summary>
                <ul class="p-2 bg-base-100 rounded-t-none z-[50]">
                  <.account_items
                    locale={@locale}
                    self_hosted={@self_hosted}
                    current_user={@current_user}
                    onboarding={@data.onboarding}
                    now={@now}
                    rails_csrf_token={@rails_csrf_token}
                    native={@native}
                  />
                </ul>
              </details>
            </li>
          </ul>
        </div>
      <% else %>
        <ul class="menu menu-horizontal bg-base-100 rounded-box px-1">
          <li><a href="/users/sign_in">{t(@locale, "shared.navbar.login", %{})}</a></li>
        </ul>
      <% end %>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :current_user, :any, required: true
  attr :onboarding, :boolean, required: true
  attr :now, :any, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :native, :boolean, default: false

  def account_items(assigns) do
    ~H"""
    <li><a href="/users/edit">{t(@locale, "shared.navbar.account", %{})}</a></li>
    <li><a href="/settings/general">{t(@locale, "shared.navbar.settings", %{})}</a></li>
    <li :if={not @self_hosted}>
      <a href={SubscriptionToken.url(@current_user, @now)}>{t(
        @locale,
        "shared.navbar.subscription",
        %{}
      )}</a>
    </li>
    <li>
      <a onclick="getting_started.showModal()" class="relative whitespace-nowrap">
        {t(@locale, "shared.navbar.get_started", %{})}
        <span
          :if={@onboarding}
          class="badge badge-secondary badge-xs absolute right-2 top-1/2 -translate-y-1/2"
        ></span>
      </a>
    </li>
    <li :if={@native}>
      <form method="post" action="/users/sign_out" class="contents">
        <input type="hidden" name="_method" value="delete" />
        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
        <button type="submit" class="w-full text-left">{t(@locale, "shared.navbar.logout", %{})}</button>
      </form>
    </li>
    <li :if={!@native}>
      <a data-turbo="false" rel="nofollow" data-method="delete" href="/users/sign_out">{t(
        @locale,
        "shared.navbar.logout",
        %{}
      )}</a>
    </li>
    """
  end

  attr :locale, :string, required: true
  attr :subscription, :map, required: true
  attr :now, :any, required: true

  def trial_state(assigns) do
    ~H"""
    <%= cond do %>
      <% @subscription.pending -> %>
        <span
          class="tooltip tooltip-bottom"
          data-tip={t(@locale, "shared.navbar.finish_setting_up_your_account", %{})}
          title={t(@locale, "shared.navbar.finish_setting_up_your_account", %{})}
        >{t(@locale, "shared.navbar.finish_signup", %{})}</span>
      <% @subscription.expired -> %>
        <span
          class="tooltip tooltip-bottom"
          data-tip={t(@locale, "shared.navbar.trial_expired", %{})}
          title={t(@locale, "shared.navbar.trial_expired", %{})}
        >{t(@locale, "shared.navbar.trial_expired_2", %{})}</span>
      <% true -> %>
        <span
          class="tooltip tooltip-bottom"
          data-tip={ends_in(@locale, @subscription, @now)}
          title={ends_in(@locale, @subscription, @now)}
        >{t(@locale, "shared.navbar.days_remaining", %{count: max(@subscription.days, 0)})}</span>
    <% end %>
    """
  end

  defp ends_in(locale, subscription, now),
    do:
      t(locale, "shared.navbar.trial_ends_in", %{
        time: TimeAgo.words(locale, subscription.active_until, now)
      })

  attr :item, :map, required: true

  def navbar_item(assigns) do
    ~H"""
    <li class="notification-item" id={"navbar_notification_#{@item.id}"}>
      <div class="divider p-0 m-0"></div>
      <a href={"/notifications/#{@item.id}"}>{@item.title}
      <div class={"badge badge-xs justify-self-end badge-#{@item.kind}"}></div></a>
    </li>
    """
  end

  attr :count, :integer, required: true

  def badge(assigns) do
    ~H"""
    <span
      id="notifications-badge"
      class={"badge badge-xs badge-primary absolute top-0 right-0 #{if @count == 0, do: "hidden"}"}
    >{count(@count)}</span>
    """
  end

  defp count(count) when count > 99, do: "99+"
  defp count(count), do: count

  defp upgrade_url(_user, %{pending: true}, _now), do: "/trial/resume"
  defp upgrade_url(user, _subscription, now), do: SubscriptionToken.url(user, now)

  defp compact(locale, %{pending: true}), do: t(locale, "helpers.application.finish_signup", %{})
  defp compact(locale, %{expired: true}), do: t(locale, "helpers.application.expired", %{})

  defp compact(locale, %{days: days}),
    do: t(locale, "helpers.application.days_left", %{count: max(days, 0)})

  defp trial_class(%{expired: true}), do: "btn-error"
  defp trial_class(%{active_until: nil}), do: "btn-error"
  defp trial_class(%{days: days}) when days in 5..8, do: "btn-info"
  defp trial_class(%{days: days}) when days in 2..4, do: "btn-warning"
  defp trial_class(%{days: days}) when days < 2, do: "btn-error"
  defp trial_class(_subscription), do: "btn-success"
end
