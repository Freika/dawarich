defmodule DawarichWeb.SharingNativeHub do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{SharingNativeActive, SharingNativeForm}
  import DawarichWeb.Icon, only: [icon: 1]
  embed_templates "sharing_native_hub/*"
  def body(assigns), do: content(assigns)
  defp s(locale, key), do: t(locale, "share_links.hubs.body." <> key, %{})
  defp l(locale, key), do: t(locale, "share_links.hubs.shared_list." <> key, %{})

  defp url(base, id),
    do: if(base in [nil, ""], do: DawarichWeb.Endpoint.url(), else: base) <> "/s/" <> id
end
