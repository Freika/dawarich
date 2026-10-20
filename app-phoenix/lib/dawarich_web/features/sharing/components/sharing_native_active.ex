defmodule DawarichWeb.SharingNativeActive do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  embed_templates "sharing_native_active/*"
  attr :share, :map, required: true
  attr :locale, :string, required: true
  attr :list, :boolean, default: false
  attr :base_url, :string, default: ""
  attr :subtitle, :any, default: nil

  def active(assigns) do
    assigns =
      assign(assigns,
        family: Dawarich.SharedLinks.FamilyAudience.family_only?(assigns.share),
        url:
          if(assigns.base_url == "", do: DawarichWeb.Endpoint.url(), else: assigns.base_url) <>
            "/s/" <> assigns.share.id
      )

    content(assigns)
  end

  def subtitle(%{type: :trip}, page, locale) do
    if Dawarich.SharedLinks.FamilyAudience.family_only?(page.share),
      do: t(locale, "shared_links.family.shared_trip", %{trip: page.trip.name}),
      else:
        t(locale, "trips.share_links.new.trip_is_shared_via_a_public_link", %{
          trip: page.trip.name
        })
  end

  def subtitle(%{type: :track}, _page, locale),
    do: t(locale, "tracks.share_links.new.this_track_is_shared_via_a_public_link", %{})

  def subtitle(%{type: :live}, _page, locale),
    do: t(locale, "share_links.lives.new.your_live_location_is_shared_via_a_public_link", %{})

  def subtitle(%{type: :timeline}, page, locale) do
    settings = page.share.settings

    range =
      DawarichWeb.SharedPages.date_range(
        locale,
        Date.from_iso8601!(settings["start_date"]),
        Date.from_iso8601!(settings["end_date"])
      )

    t(locale, "helpers.shared_links.timeline_subtitle", %{range: range})
  end

  def subtitle(_, _, _), do: nil

  attr :share, :map, required: true
  attr :locale, :string, required: true
  attr :field, :string, required: true
  attr :url, :string, required: true
  attr :family, :boolean, required: true

  def reveal(assigns) do
    ~H"""
    <div
      id={"native-sharing-reveal-#{@share.id}-#{@field}"}
      phx-hook="SharingReveal"
      data-url={"/native/sharing/#{@share.id}/#{@field}"}
      data-copied-label={t(@locale, "javascript.messages.copied_to_clipboard", %{})}
      data-failed-label={t(@locale, "javascript.messages.failed_to_copy_please_copy_manually", %{})}
    >
      <label
        class="text-xs font-medium text-base-content/60 uppercase tracking-wide"
        for={if @field == "url", do: "share-url", else: "share-phrase"}
      >{if @field == "phrase",
        do: s(@locale, "magic_phrase"),
        else:
          if(@family,
            do: t(@locale, "shared_links.family.link", %{}),
            else: s(@locale, "public_link")
          )}</label>
      <div class="join w-full mt-1">
        <input
          id={if @field == "url", do: "share-url", else: "share-phrase"}
          type="text"
          readonly
          value={if @field == "url", do: @url, else: ""}
          data-private-reveal={if @field == "phrase", do: "true"}
          class="input input-bordered join-item flex-1 font-mono text-sm"
        />
        <button
          type="button"
          data-reveal
          class="btn btn-outline join-item"
          title={if @field == "url", do: s(@locale, "copy_link")}
          aria-label={
            s(
              @locale,
              if(@field == "phrase",
                do: "copy_magic_phrase",
                else: if(@family, do: "copy_link", else: "copy_public_link")
              )
            )
          }
        ><.icon name="copy" class="w-4 h-4" /></button>
        <a
          :if={@field == "url"}
          href={@url}
          target="_blank"
          rel="noopener"
          class="btn btn-outline join-item"
          title={s(@locale, "open_in_new_tab")}
          aria-label={s(@locale, "open_in_new_tab")}
        ><.icon name="external-link" class="w-4 h-4" /></a>
      </div>
      <span
        role="status"
        aria-live="polite"
        data-status
        class="block min-w-0 max-w-full whitespace-normal [overflow-wrap:anywhere] text-sm"
      ></span>
    </div>
    """
  end

  defp s(locale, key, attrs \\ %{}), do: t(locale, "shared_links.modal_active." <> key, attrs)

  defp last_viewed(locale, at),
    do:
      t(locale, "common.time_ago", %{
        time: DawarichWeb.TimeAgo.words(locale, at, DateTime.utc_now())
      })
end
