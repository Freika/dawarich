defmodule DawarichWeb.NavbarAccount do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.SubscriptionToken
  alias Phoenix.LiveView.JS

  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :current_user, :any, required: true
  attr :onboarding, :boolean, required: true
  attr :now, :any, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :native, :boolean, default: false
  attr :http, :boolean, default: false

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
      <button
        :if={@http}
        type="button"
        class="relative whitespace-nowrap"
        data-auth-open-dialog="getting_started"
      >
        {t(@locale, "shared.navbar.get_started", %{})}
        <span
          :if={@onboarding}
          class="badge badge-secondary badge-xs absolute right-2 top-1/2 -translate-y-1/2"
        ></span>
      </button>
      <.dynamic_tag
        :if={!@http}
        tag_name={if @native, do: "button", else: "a"}
        {if @native, do: %{type: "button"}, else: %{}}
        onclick={!@native && "getting_started.showModal()"}
        phx-click={@native && JS.dispatch("dawarich:open-dialog", to: "#getting_started")}
        class="relative whitespace-nowrap"
      >
        {t(@locale, "shared.navbar.get_started", %{})}
        <span
          :if={@onboarding}
          class="badge badge-secondary badge-xs absolute right-2 top-1/2 -translate-y-1/2"
        ></span>
      </.dynamic_tag>
    </li>
    <li :if={@http}>
      <DawarichWeb.AuthHttpChrome.sign_out locale={@locale} rails_csrf_token={@rails_csrf_token} />
    </li>
    <li :if={@native && !@http}>
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
end
