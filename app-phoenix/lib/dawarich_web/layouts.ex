defmodule DawarichWeb.Layouts do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Chrome
  import DawarichWeb.Head
  import DawarichWeb.Translate, only: [t: 3]
  embed_templates "layouts/*"

  def theme(%{theme: "light"}), do: "dawarich"
  def theme(_), do: "dawarich-dark"

  def page_title(locale, nil), do: t(locale, "common.app_name", %{})

  def page_title(locale, title) do
    app_name = t(locale, "common.app_name", %{})
    t(locale, "helpers.application.full_title", %{page_title: title, app_name: app_name})
  end

  def importmap do
    versions = DawarichWeb.Assets.script_versions()

    Jason.encode!(%{
      "imports" => %{
        "app" => "/phoenix/js/app.js?vsn=#{versions.app}",
        "phoenix" => "/phoenix/js/phoenix.mjs?vsn=#{versions.phoenix}",
        "phoenix_live_view" => "/phoenix/js/phoenix_live_view.esm.js?vsn=#{versions.live_view}"
      }
    })
  end

  def locale_path(path, query_params, locale) do
    query = query_params |> Map.put("locale", locale) |> URI.encode_query()
    path <> "?" <> query
  end
end
