defmodule DawarichWeb.ShareHub do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.{SharedPages, ShareLinkActive, ShareLinkForm}

  embed_templates "share_hub/*"

  def paths(type, query \\ "") do
    base = if is_integer(type), do: "/trips/#{type}/share_link", else: "/share_links/#{type}"

    %{
      create: base <> query,
      destroy: base <> query,
      revoke: base <> "/revoke" <> query,
      regenerate: base <> "/regenerate" <> query,
      regenerate_phrase: base <> "/regenerate_phrase" <> query
    }
  end

  def query(hub),
    do:
      "?" <>
        URI.encode_query([{"end_date", hub.end_date}, {"hub", 1}, {"start_date", hub.start_date}])

  defp s(ctx, part, key), do: t(ctx.locale, "share_links.hubs.#{part}.#{key}", %{})

  defp timeline_subtitle(ctx, share) do
    first = Date.from_iso8601!(share.settings["start_date"])
    last = Date.from_iso8601!(share.settings["end_date"])
    range = SharedPages.date_range(ctx.locale, first, last)
    t(ctx.locale, "helpers.shared_links.timeline_subtitle", %{range: range})
  end
end
