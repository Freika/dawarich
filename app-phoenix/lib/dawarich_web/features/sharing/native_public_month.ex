defmodule DawarichWeb.NativePublicMonth do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{
    Assets,
    NativePublicChrome,
    NativePublicContent,
    NativeMapPreview,
    LocalizedDate
  }

  def document(assigns) do
    title =
      LocalizedDate.l(
        assigns.locale,
        Date.new!(assigns.page.stat.year, assigns.page.stat.month, 1),
        "month_year"
      )

    assigns =
      assign(assigns,
        title: title,
        config: %{
          "kind" => "stats",
          "uuid" => assigns.uuid,
          "interactive" => true,
          "bounds" =>
            Map.new(assigns.page.bounds || %{}, fn {key, value} -> {to_string(key), value} end),
          "range" => %{"timezone" => assigns.page.timezone}
        }
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
        <script type="module" src={Assets.native_path("auth_http.js")}>
        </script>
      </head>
      <body class="bg-base-100 min-w-0" style="overflow-wrap:anywhere">
        <NativePublicChrome.header {@chrome} />
        <main class="container mx-auto min-w-0">
          <NativePublicContent.month page={@page} locale={@locale}>
            <:map>
              <NativeMapPreview.preview
                id="public-month-map"
                config={@config}
                locale={@locale}
                class="h-96 w-full min-w-0 bg-base-200 rounded-lg"
              />
            </:map>
          </NativePublicContent.month>
        </main>
        <NativePublicChrome.footer locale={@locale} />
      </body>
    </html>
    """
  end
end
