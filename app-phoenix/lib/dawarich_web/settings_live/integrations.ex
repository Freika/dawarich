defmodule DawarichWeb.SettingsLive.Integrations do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.IntegrationPanes, only: [service_icon: 1, status_icon: 1, pane: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts, only: [navigation: 1, two_factor_available?: 0]

  alias Dawarich.{Entitlements, Integrations}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{StatsFormat, TrekPane}

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    if params["service"] == "geocoding" and user.admin == true and socket.assigns.self_hosted,
      do: {:ok, redirect(socket, to: "/admin/settings")},
      else: {:ok, assign(socket, page(user, params, socket.assigns))}
  end

  def page(user, params, %{locale: locale, now: now, self_hosted: self_hosted} = context) do
    page = %{
      page_title: t(locale, "settings.integrations.index.settings", %{}),
      rails_js: true,
      two_factor: Map.get_lazy(context, :two_factor, &two_factor_available?/0),
      pro_required: not Entitlements.full_access?(user, self_hosted, now)
    }

    if page.pro_required do
      page
    else
      service = Integrations.service(params["service"])
      sources = Integrations.trek_sources(user)

      Map.merge(page, %{
        service: service,
        statuses: Integrations.statuses(user, sources),
        sources: if(service == "trek", do: sources, else: []),
        synced:
          if(service in ~w(airtrail teslamate),
            do: Integrations.synced_text(locale, user, service <> "_last_synced_at")
          )
      })
    end
  end

  def form_user(user) do
    if Dawarich.Standalone.enabled?() do
      secrets =
        ~w(immich_api_key photoprism_api_key airtrail_api_key teslamate_password teslamate_api_token)

      settings =
        Map.new(user.settings || %{}, fn {key, value} ->
          {key, if(key in secrets and Ruby.present?(value), do: "********", else: value)}
        end)

      %{user | settings: settings}
    else
      user
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :upgrade,
        assigns.pro_required &&
          StatsFormat.upgrade_url(
            assigns.current_user,
            assigns.now,
            assigns.self_hosted,
            "settings",
            "integrations"
          )
      )

    ~H"""
    <div class="min-h-content w-full my-5">
      <.page_header title={t(@locale, "settings.integrations.index.user_settings", %{})} />
      <.navigation
        locale={@locale}
        active="integrations"
        self_hosted={@self_hosted}
        admin={@current_user.admin == true}
        two_factor={@two_factor}
      />

      <%= if @pro_required do %>
        <div class="rounded-box border border-base-content/10 bg-base-200">
          <div class="card-body text-center items-center py-12">
            <h2 class="text-2xl flex font-bold mb-2 items-center">
              <.icon name="shield-check" class="mr-2 text-primary" /> {t(
                @locale,
                "settings.integrations.index.immich_photoprism_integrations",
                %{}
              )}
            </h2>
            <p class="text-base-content/60 mb-6 max-w-md">
              {t(
                @locale,
                "settings.integrations.index.connect_your_photo_management_tools_to_see_your_photos_on",
                %{}
              )}
            </p>
            <a href={@upgrade} class="btn btn-primary">
              {t(@locale, "settings.integrations.index.upgrade_to_pro", %{})}
            </a>
          </div>
        </div>
      <% else %>
        <div class="flex flex-col lg:flex-row gap-6 items-start">
          <nav
            class="w-full lg:w-64 shrink-0 space-y-2"
            aria-label={t(@locale, "settings.integrations.index.services_nav", %{})}
          >
            <a
              :for={service <- Integrations.services()}
              class={"flex items-center gap-3 rounded-box border p-3 transition-colors " <> if(service == @service, do: "border-primary/60 bg-base-200", else: "border-base-content/10 hover:border-base-content/25")}
              aria-current={service == @service && "page"}
              data-testid={"integration-" <> service}
              data-status={@statuses[service]}
              href={"/settings/integrations?service=" <> service}
            >
              <.service_icon service={service} css="size-5" />
              <span class="font-medium flex-1 truncate">{t(
                @locale,
                "settings.integrations.index.services.#{service}",
                %{}
              )}</span>
              <.status_icon locale={@locale} status={@statuses[service]} />
            </a>

            <div :if={@self_hosted} class="pt-2 mt-2 border-t border-base-content/10">
              <%= if @current_user.admin == true do %>
                <a
                  class="flex items-center gap-3 rounded-box border border-base-content/10 p-3 transition-colors hover:border-base-content/25"
                  data-testid="integration-geocoding-moved"
                  href="/admin/settings"
                >
                  <.icon name="map-pin" class="size-5 shrink-0 text-base-content/70" />
                  <span class="flex-1 min-w-0">
                    <span class="block font-medium truncate">{t(
                      @locale,
                      "settings.integrations.index.geocoding",
                      %{}
                    )}</span>
                    <span class="block text-xs text-base-content/70">{t(
                      @locale,
                      "settings.integrations.index.geocoding_moved_to_instance",
                      %{}
                    )}</span>
                  </span>
                  <.icon name="arrow-right" class="size-4 shrink-0 text-base-content/50" />
                </a>
              <% else %>
                <div
                  class="flex items-center gap-3 rounded-box border border-dashed border-base-content/10 p-3"
                  data-testid="integration-geocoding-moved"
                >
                  <.icon name="map-pin" class="size-5 shrink-0 text-base-content/50" />
                  <span class="flex-1 min-w-0">
                    <span class="block font-medium truncate text-base-content/70">{t(
                      @locale,
                      "settings.integrations.index.geocoding",
                      %{}
                    )}</span>
                    <span class="block text-xs text-base-content/70">{t(
                      @locale,
                      "settings.integrations.index.geocoding_managed_by_admin",
                      %{}
                    )}</span>
                  </span>
                </div>
              <% end %>
            </div>
          </nav>

          <div class="flex-1 min-w-0 w-full">
            <TrekPane.pane
              :if={@service == "trek"}
              locale={@locale}
              sources={@sources}
              rails_csrf_token={@rails_csrf_token}
            />
            <.pane
              :if={@service != "trek"}
              service={@service}
              locale={@locale}
              user={form_user(@current_user)}
              rails_csrf_token={@rails_csrf_token}
              synced={@synced}
            />
          </div>
        </div>

        <div
          :if={not @self_hosted and Ruby.present?(@current_user.provider)}
          class="rounded-box border border-base-content/10 bg-base-200 mt-6 max-w-3xl"
        >
          <div class="card-body">
            <h2 class="text-lg font-semibold flex items-center">
              <.icon name="link" class="text-primary mr-2 size-5" /> {t(
                @locale,
                "settings.integrations.index.connected_accounts",
                %{}
              )}
            </h2>
            <p class="text-sm text-base-content/60">
              {t(
                @locale,
                "settings.integrations.index.you_ve_connected_your_account_using_the_following_oauth_provider",
                %{}
              )}
              <strong>{String.capitalize(@current_user.provider)}</strong>
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
