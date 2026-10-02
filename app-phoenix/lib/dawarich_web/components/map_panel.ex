defmodule DawarichWeb.MapPanel do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapLayersTab, only: [layers_tab: 1]
  import DawarichWeb.MapSettingsAppearance, only: [appearance: 1]
  import DawarichWeb.MapSettingsSections, only: [map_sections: 1]
  import DawarichWeb.MapSettingsMore, only: [more_settings: 1]
  import DawarichWeb.MapTimelineTab, only: [timeline_tab: 1]
  import DawarichWeb.MapToolsTab, only: [tools_tab: 1]

  alias DawarichWeb.Icon

  @links [
    {"community",
     [
       {"https://discord.gg/pHsBjpt5J8", "discord"},
       {"https://x.com/freymakesstuff", nil},
       {"https://github.com/Freika/dawarich", "github"},
       {"https://mastodon.social/@dawarich", "mastodon"}
     ]},
    {"docs",
     [
       {"https://dawarich.app/docs/intro", "tutorial"},
       {"https://dawarich.app/docs/tutorials/import-existing-data", "import_existing_data"},
       {"https://dawarich.app/docs/tutorials/export-your-data", "exporting_data"},
       {"https://dawarich.app/docs/FAQ", "faq"},
       {"https://dawarich.app/contact", "contact"}
     ]},
    {"more_2",
     [
       {"https://dawarich.app/privacy-policy", "privacy_policy"},
       {"https://dawarich.app/terms-and-conditions", "terms_and_conditions"},
       {"https://dawarich.app/refund-policy", "refund_policy"},
       {"https://dawarich.app/impressum", "impressum"},
       {"https://dawarich.app/blog", "blog"}
     ]}
  ]

  attr :page, :map, required: true
  attr :params, :map, required: true
  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :rails_csrf_token, :string, default: nil

  def settings_panel(assigns) do
    assigns = assign(assigns, timeline: assigns.params["panel"] == "timeline", links: @links)

    ~H"""
    <div
      id="map-settings-panel"
      data-turbo-permanent
      class={"map-control-panel#{if @timeline, do: " open timeline-expanded"}"}
      data-maps--maplibre-target="settingsPanel"
      data-controller="map-panel"
    >
      <div class="panel-content">
        <div class="panel-header">
          <button
            class="btn btn-ghost btn-sm btn-circle"
            data-action="click->maps--maplibre#toggleSettings"
            title={s(@locale, "close_panel")}
          >
            <Icon.icon name="x" class="size-6" />
          </button>
          <h3 class="panel-title" data-map-panel-target="title">{s(@locale, "layers")}</h3>
        </div>
        <div class="panel-body">
          <div class="tab-content" data-tab-content="search" data-map-panel-target="tabContent">
            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">{s(@locale, "search_for_a_place")}</span>
              </label>
              <div class="relative">
                <input
                  type="text"
                  placeholder={s(@locale, "enter_name_of_a_place")}
                  class="input input-bordered w-full"
                  data-maps--maplibre-target="searchInput"
                  autocomplete="off"
                />
                <div
                  class="absolute z-50 w-full mt-1 bg-base-100 rounded-lg shadow-lg border border-base-300 hidden max-height:400px;  overflow-y-auto"
                  data-maps--maplibre-target="searchResults"
                >
                </div>
              </div>
              <p class="text-xs text-base-content/60 mt-2">
                {s(@locale, "search_for_a_location_to_find_places_you_visited")}
              </p>
            </div>
          </div>
          <.layers_tab page={@page} locale={@locale} timeline={@timeline} />
          <div class="tab-content" data-tab-content="settings" data-map-panel-target="tabContent">
            <form
              data-controller="map-settings-dirty"
              data-action="submit->maps--maplibre#updateAdvancedSettings input->map-settings-dirty#check change->map-settings-dirty#check"
              class="space-y-4"
            >
              <.appearance page={@page} locale={@locale} />
              <.map_sections page={@page} locale={@locale} />
              <.more_settings page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
            </form>
          </div>
          <.timeline_tab page={@page} locale={@locale} timeline={@timeline} />
          <.tools_tab page={@page} locale={@locale} />
          <div
            :if={!@self_hosted}
            class="tab-content"
            data-tab-content="links"
            data-map-panel-target="tabContent"
          >
            <div class="space-y-6">
              <%= for {{heading, links}, index} <- Enum.with_index(@links) do %>
                <div :if={index > 0} class="divider"></div>
                <div>
                  <h4 class="font-semibold text-base mb-3">{s(@locale, heading)}</h4>
                  <div class="flex flex-col gap-2">
                    <a
                      :for={{href, key} <- links}
                      href={href}
                      target="_blank"
                      class="link-hover text-sm"
                    >{if key,
                      do: s(@locale, key),
                      else: "X"}</a>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
