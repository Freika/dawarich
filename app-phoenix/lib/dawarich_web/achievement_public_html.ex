defmodule DawarichWeb.AchievementPublicHTML do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.AchievementCard, only: [card: 1]
  import DawarichWeb.Head, only: [favicon: 1, pwa_meta: 1]
  import DawarichWeb.SharedPages, only: [l: 2, cta: 1, cta: 2, importmap: 0, translations: 1]
  alias DawarichWeb.Assets
  alias Dawarich.Achievements.UiText

  embed_templates "achievement_public/*"

  def html(%{embed: true} = assigns), do: assigns |> embed() |> Phoenix.HTML.Safe.to_iodata()
  def html(assigns), do: assigns |> document() |> Phoenix.HTML.Safe.to_iodata()

  def head_assets(assigns) do
    assigns =
      assign(assigns, :url, assigns.base_url <> "/shared/achievements/" <> assigns.view.uuid)

    ~H"""
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex, nofollow" />
    <title>{@view.name} — Dawarich</title>
    <%= unless @embed do %>
      <meta name="csrf-param" content="authenticity_token" /><meta
        name="csrf-token"
        content={@rails_csrf_token}
      />
      <.favicon /><.pwa_meta locale={@locale} />
    <% end %>
    <link
      :for={name <- ~w(tailwind inter-font application)}
      rel="stylesheet"
      href={Assets.stylesheet_path(name <> ".css")}
      data-turbo-track="reload"
    />
    <script
      :if={!@embed}
      id="i18n-translations"
      type="application/json"
      data-turbo-track="reload"
      phx-no-format
    ><%= Phoenix.HTML.raw(translations(@locale)) %></script>
    <script type="importmap" data-turbo-track="reload" phx-no-format><%= Phoenix.HTML.raw(importmap()) %></script>
    <script type="module">
      import "application"
    </script>
    <link
      :for={name <- ~w(achievements achievements_spectral achievements_unlocks)}
      rel="stylesheet"
      href={Assets.stylesheet_path(name <> ".css")}
      data-turbo-track="reload"
    />
    <meta property="og:title" content={@view.name <> " — Dawarich"} />
    <meta property="og:description" content={@view.description} />
    <meta property="og:type" content="website" />
    <meta property="og:url" content={@url} />
    <meta property="og:image" content={@url <> "/og.png"} />
    <meta property="og:image:type" content="image/png" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:image:alt" content={@view.name <> " — " <> @view.metric} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:image" content={@url <> "/og.png"} />
    """
  end

  def tracked(locale),
    do:
      UiText.t(locale, "public.tracked_with_html", %{
        "link" => ~s(<a href="https://dawarich.app">Dawarich</a>)
      })
      |> Phoenix.HTML.raw()
end
