defmodule DawarichWeb.Layouts do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Chrome
  import DawarichWeb.Head
  import DawarichWeb.Navbar, only: [navbar: 1]
  import DawarichWeb.OnboardingModal, only: [onboarding_modal: 1]
  import DawarichWeb.Translate, only: [t: 3]
  embed_templates "layouts/*"

  def theme(%{theme: "light"}), do: "dawarich"
  def theme(_), do: "dawarich-dark"

  def page_title(locale, nil), do: t(locale, "common.app_name", %{})

  def page_title(locale, title) do
    app_name = t(locale, "common.app_name", %{})
    t(locale, "helpers.application.full_title", %{page_title: title, app_name: app_name})
  end

  def importmap(rails_js \\ false) do
    versions = DawarichWeb.Assets.script_versions()

    phoenix = %{
      "app" => "/phoenix/js/app.js?vsn=#{versions.app}",
      "phoenix" => "/phoenix/js/phoenix.mjs?vsn=#{versions.phoenix}",
      "phoenix_live_view" => "/phoenix/js/phoenix_live_view.esm.js?vsn=#{versions.live_view}"
    }

    imports =
      if rails_js, do: Map.merge(DawarichWeb.Assets.rails_imports(), phoenix), else: phoenix

    Jason.encode!(%{"imports" => imports})
  end

  def rails_modules?(assigns),
    do: assigns[:rails_js] == true or not is_nil(assigns[:current_user])

  def rails_translations(locale) do
    base =
      case Dawarich.I18n.t(locale, "javascript") do
        {:ok, %{} = tree} -> tree
        _ -> %{}
      end

    extra =
      Map.new(~w(transportation_modes visit_statuses battery_statuses), fn key ->
        case Dawarich.I18n.t(locale, key) do
          {:ok, value} -> {key, value}
          _ -> {key, %{}}
        end
      end)

    base |> Map.merge(extra) |> Jason.encode!(escape: :html_safe)
  end

  def locale_path(path, query_params, locale) do
    query = query_params |> Map.put("locale", locale) |> DawarichWeb.Params.to_query()
    path <> "?" <> query
  end

  def navbar_data(assigns) do
    case assigns[:navbar] do
      navbar when is_map(navbar) ->
        navbar

      _ ->
        if assigns[:current_user],
          do: raise("Dawarich.Navbar.load/2 was not preloaded for a signed-in render"),
          else: Dawarich.Navbar.load(nil, now: assigns.now, self_hosted: assigns.self_hosted)
    end
  end
end
