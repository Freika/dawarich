defmodule DawarichWeb.NativeMapLinks do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

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

  attr :locale, :string, required: true

  def links(assigns) do
    assigns = assign(assigns, :links, @links)

    ~H"""
    <div id="native-map-links" class="space-y-6">
      <%= for {{heading, links}, index} <- Enum.with_index(@links) do %>
        <div :if={index > 0} class="divider"></div>
        <div>
          <h4 class="font-semibold text-base mb-3">{label(@locale, heading)}</h4>
          <div class="flex flex-col gap-2">
            <a
              :for={{href, key} <- links}
              href={href}
              target="_blank"
              rel="noopener noreferrer"
              class="link-hover text-sm"
            >{if key, do: label(@locale, key), else: "X"}</a>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp label(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
