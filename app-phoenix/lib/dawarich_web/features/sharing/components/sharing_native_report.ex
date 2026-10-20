defmodule DawarichWeb.SharingNativeReport do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  embed_templates "sharing_native_report/*"
  attr :resource, :map, required: true
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, default: ""
  attr :close, :any, default: nil
  attr :errors, :list, default: []
  attr :native_copy, :boolean, default: false

  def form(assigns) do
    settings = assigns.page[:settings] || %{}

    assigns =
      assign(assigns,
        enabled: assigns.page[:enabled] || settings["enabled"] == true,
        expiration:
          settings["expiration"] || if(assigns.resource.type == :month, do: "1h", else: "24h"),
        scope:
          if(assigns.resource.type == :digest,
            do: "users.digests.show",
            else: "shared.sharing_modal"
          ),
        url: url(assigns.resource, assigns.page.uuid, assigns.base_url),
        close: assigns.close || DawarichWeb.SharingResource.back(assigns.resource)
      )

    if assigns.resource.type == :achievement, do: achievement(assigns), else: document(assigns)
  end

  defp url(_, nil, _), do: ""
  defp url(%{type: :achievement}, uuid, _), do: "/shared/achievements/" <> uuid

  defp url(%{type: type}, uuid, base),
    do:
      if(base == "", do: DawarichWeb.Endpoint.url(), else: base) <>
        "/shared/" <> %{month: "month", digest: "digest"}[type] <> "/" <> uuid

  defp s(locale, scope, key), do: t(locale, scope <> "." <> key, %{})
end
