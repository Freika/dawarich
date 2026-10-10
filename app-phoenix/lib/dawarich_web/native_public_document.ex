defmodule DawarichWeb.NativePublicDocument do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{AchievementPublicHTML, PublicDigest, Assets, SharedPages}
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, required: true
  attr :uuid, :string, required: true
  attr :embed, :boolean, default: false

  def document(%{page: %{card: _} = page} = assigns) do
    AchievementPublicHTML.html(%{
      __changed__: nil,
      view: page,
      locale: page.locale,
      base_url: assigns.base_url,
      rails_csrf_token: "",
      embed: assigns.embed,
      native: true
    })
    |> Phoenix.HTML.raw()
  end

  def document(assigns) do
    assigns =
      assign(assigns,
        title:
          t(assigns.locale, "users.digests.public_year.year_year_in_review", %{
            year: assigns.page.digest.year
          })
      )

    ~H"""
    <!DOCTYPE html>
    <html lang={@locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex, nofollow" />
        <title>{@title} — Dawarich</title>
        <link
          :for={name <- ~w(tailwind inter-font application)}
          rel="stylesheet"
          href={Assets.stylesheet_path(name <> ".css")}
        />
        <script type="module" src={Assets.native_path("public_charts.js")}>
        </script>
        <meta property="og:type" content="article" />
        <meta property="og:title" content={@title} />
        <meta property="og:description" content={@title} />
        <meta property="og:image" content={@base_url <> Assets.stylesheet_path("og_default.png")} />
        <meta name="twitter:card" content="summary_large_image" />
      </head>
      <body class="bg-base-100 min-w-0" style="overflow-wrap:anywhere">
        <header class="flex flex-wrap gap-3 p-4 min-w-0">
          <a href="/" class="btn btn-ghost">Dawarich</a>
          <a href={SharedPages.cta("header")} class="btn whitespace-normal">{SharedPages.l(
            @locale,
            "try_dawarich_cloud"
          )}</a>
        </header>
        <main class="min-w-0">
          <PublicDigest.document
            digest={@page.digest}
            full={@page.full}
            totals={@page.totals}
            unit={@page.unit}
            locale={@locale}
            table={Dawarich.CountryNames.table()}
            native
          />
          <nav
            class="flex flex-wrap justify-center gap-3"
            aria-label={t(@locale, "achievements.ui.collection_pages", %{})}
          >
            <a :if={@page.page > 1} rel="prev" href={"?page=#{@page.page - 1}"}>{t(
              @locale,
              "achievements.ui.prev_page",
              %{}
            )}</a>
            <a :if={@page.more} rel="next" href={"?page=#{@page.page + 1}"}>{t(
              @locale,
              "achievements.ui.next_page",
              %{}
            )}</a>
          </nav>
        </main>
        <footer class="p-6 flex flex-wrap gap-3 min-w-0">
          <p>{SharedPages.l(@locale, "shared_with_dawarich")}</p>
          <a href={SharedPages.cta("footer_cta")}>{SharedPages.l(@locale, "try_dawarich_cloud")}</a>
        </footer>
      </body>
    </html>
    """
  end
end
