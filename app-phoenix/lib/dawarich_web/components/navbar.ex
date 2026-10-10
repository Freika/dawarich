defmodule DawarichWeb.Navbar do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.NavbarEnd, only: [navbar_end: 1]
  import DawarichWeb.NavbarParts

  alias DawarichWeb.Icon

  @my_data ~w(points places imports exports tags)

  attr :current_user, :any, required: true
  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :request_path, :string, required: true
  attr :base_url, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :now, :any, required: true
  attr :native, :boolean, default: false

  def navbar(assigns) do
    ~H"""
    <div class="navbar bg-base-100 h-16">
      <div class="navbar-start">
        <details class="dropdown xl:hidden">
          <summary
            class="btn btn-ghost list-none"
            aria-label={t(@locale, "shared.navbar.open_navigation_menu", %{})}
            aria-controls="mobile-navigation-menu"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            ><path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 6h16M4 12h8m-8 6h16"
            /></svg>
          </summary>
          <ul
            id="mobile-navigation-menu"
            class="menu menu-sm dropdown-content mt-3 z-[50] p-2 shadow bg-base-100 rounded-box w-52"
          >
            <.main_links
              mobile
              locale={@locale}
              request_path={@request_path}
              base_url={@base_url}
              current_user={@current_user}
              family={@data[:family]}
              native={@native}
            />
            <li :if={@data[:subscription]}>
              <a
                class="btn btn-sm btn-success"
                href={Dawarich.SubscriptionToken.url(@current_user, @now)}
              >{t(@locale, "shared.navbar.subscribe", %{})}</a>
            </li>
            <%= if @current_user do %>
              <div class="divider my-1"></div>
              <li>
                <.theme_toggle
                  locale={@locale}
                  theme={@current_user.theme}
                  class="flex items-center gap-2"
                  label
                  native={@native}
                />
              </li>
              <li>
                <details>
                  <summary>
                    <Icon.icon name="message-circle-question-mark" class="size-6" /> {t(
                      @locale,
                      "shared.navbar.help",
                      %{}
                    )}
                  </summary>
                  <ul class="p-2 bg-base-100"><.help_links locale={@locale} /></ul>
                </details>
              </li>
            <% end %>
          </ul>
        </details>
        <a
          class="btn btn-ghost normal-case text-xl gap-2"
          href={if @current_user, do: "/map/v2", else: "/"}
        >
          <img
            alt={t(@locale, "shared.navbar.dawarich_logo", %{})}
            class="h-8 w-8 rounded-[20%]"
            src={DawarichWeb.Assets.stylesheet_path("logo.svg")}
          />
          <span>{t(@locale, "shared.navbar.dawarich", %{})}<sup>β</sup></span>
        </a>
        <.version_indicator
          locale={@locale}
          version={@data.version}
          rails_csrf_token={@rails_csrf_token}
          native={@native}
        />
        <div :if={@current_user} class="hidden xl:block">
          <.theme_toggle locale={@locale} theme={@current_user.theme} native={@native} />
        </div>
      </div>
      <div class="navbar-center hidden xl:flex">
        <ul class="menu menu-horizontal px-1">
          <.main_links
            mobile={false}
            locale={@locale}
            request_path={@request_path}
            base_url={@base_url}
            current_user={@current_user}
            family={@data[:family]}
            native={@native}
          />
        </ul>
      </div>
      <.navbar_end
        current_user={@current_user}
        data={@data}
        locale={@locale}
        self_hosted={@self_hosted}
        now={@now}
        rails_csrf_token={@rails_csrf_token}
        native={@native}
      />
    </div>
    """
  end

  attr :mobile, :boolean, default: false
  attr :locale, :string, required: true
  attr :request_path, :string, required: true
  attr :base_url, :string, required: true
  attr :current_user, :any, required: true
  attr :family, :any, required: true
  attr :native, :boolean, default: false

  def main_links(assigns) do
    assigns =
      assign(assigns,
        my_data: @my_data,
        home: if(assigns.family && assigns.family.available, do: "/family", else: "/family/new")
      )

    ~H"""
    <li>
      <a class={link_class(@mobile, @request_path, "/map/v2")} href="/map/v2">{t(
        @locale,
        "shared.navbar.map",
        %{}
      )}</a>
    </li>
    <li>
      <a class={link_class(@mobile, @request_path, "/trips")} href={@base_url <> "/trips"}>{t(
        @locale,
        "shared.navbar.trips",
        %{}
      )}</a>
    </li>
    <li>
      <a class={link_class(@mobile, @request_path, "/stats")} href={@base_url <> "/stats"}>{t(
        @locale,
        "shared.navbar.stats",
        %{}
      )}</a>
    </li>
    <li>
      <a class={link_class(@mobile, @request_path, "/insights")} href={@base_url <> "/insights"}>{t(
        @locale,
        "shared.navbar.insights_sup_sup_html",
        %{}
      )}</a>
    </li>
    <li>
      <a class={link_class(@mobile, @request_path, "/achievements")} href="/achievements">{t(
        @locale,
        "achievements.ui.title",
        %{}
      )}</a>
    </li>
    <li :if={@current_user && (@family.available or @family.member)}>
      <%= if @family.member do %>
        <a
          class={"#{link_class(@mobile, @request_path, @home)} flex items-center space-x-2"}
          href={@home}
        >
          <span>{t(@locale, "shared.navbar.family", %{})}<sup :if={not @mobile}>α</sup></span>
          <.family_indicator locale={@locale} sharing={@family.sharing} native={@native} />
        </a>
      <% else %>
        <a class={link_class(@mobile, @request_path, "/family/new")} href="/family/new">{t(
          @locale,
          "shared.navbar.family_sup_sup_html",
          %{}
        )}</a>
      <% end %>
    </li>
    <li>
      <details>
        <summary>{t(@locale, "shared.navbar.my_data", %{})}</summary>
        <ul class={
          if @mobile, do: "p-2 bg-base-100", else: "p-2 bg-base-100 rounded-box shadow-md z-[50]"
        }>
          <li :for={key <- @my_data}>
            <a class={active(@request_path, "/" <> key)} href={@base_url <> "/" <> key}>{t(
              @locale,
              "shared.navbar.#{key}",
              %{}
            )}</a>
          </li>
        </ul>
      </details>
    </li>
    """
  end

  defp link_class(true, request_path, path), do: active(request_path, path)
  defp link_class(false, request_path, path), do: "mx-1 " <> active(request_path, path)

  defp active(request_path, path) do
    current =
      if byte_size(request_path) > 1,
        do: String.replace_suffix(request_path, "/", ""),
        else: request_path

    if current == path, do: "btn-active", else: ""
  end
end
