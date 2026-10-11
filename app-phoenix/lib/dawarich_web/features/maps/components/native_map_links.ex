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
    <section id="native-map-links" class="w-full min-w-0 max-w-96 bg-base-100 p-3 space-y-6">
      <div :for={{heading, links} <- @links} class="min-w-0">
        <h2 class="font-semibold [overflow-wrap:anywhere]">{label(@locale, heading)}</h2>
        <div class="flex min-w-0 flex-col gap-2">
          <a
            :for={{href, key} <- links}
            href={href}
            target="_blank"
            rel="noopener noreferrer"
            class="link [overflow-wrap:anywhere]"
          >{if key, do: label(@locale, key), else: "X"}</a>
        </div>
      </div>
    </section>
    """
  end

  defp label(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
