defmodule DawarichWeb.NativeAchievementNavigation do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  def sidebar(assigns) do
    active = assigns.view[:sidebar_key]
    continent = Enum.find(assigns.view.continents, &(&1["key"] == active))

    assigns =
      assign(assigns,
        active: active,
        active_name: if(continent, do: continent["place"], else: s(assigns.locale, "summary"))
      )

    ~H"""
    <aside class="ach-navigation">
      <nav class="ach-side ach-side--desktop" aria-label={s(@locale, "collection_navigation")}>
        <.links {assigns} />
      </nav>
      <details class="ach-mobile-nav">
        <summary>
          <span>{s(@locale, "browse")}</span><strong>{@active_name}</strong><.icon
            name="chevron-down"
            class="w-4 h-4"
            aria_hidden
          />
        </summary>
        <nav class="ach-side" aria-label={s(@locale, "collection_navigation")}>
          <.links {assigns} />
        </nav>
      </details>
    </aside>
    """
  end

  def links(assigns) do
    ~H"""
    <.link
      patch="/achievements"
      class={["ach-side-link", is_nil(@active) && "ach-side-link--active"]}
      aria-current={is_nil(@active) && "page"}
    >
      <span>{s(@locale, "summary")}</span><span class="ach-side-count">{@view.summary.earned_countries}/{@view.summary.total_countries}</span>
    </.link>
    <div class="ach-side-group">{s(@locale, "continents")}</div>
    <.link
      :for={set <- @view.continents}
      patch={"/achievements/" <> set["key"]}
      class={["ach-side-link", @active == set["key"] && "ach-side-link--active"]}
      aria-current={@active == set["key"] && "page"}
    >
      <span>{set["place"]}</span><span class="ach-side-count">{min(set["count"], set["target"])}/{set[
        "target"
      ]}</span>
      <span class="ach-side-bar" aria-hidden="true"><span style={"width: #{set["percent"]}%;"}></span></span>
    </.link>
    """
  end

  defp s(locale, key), do: t(locale, "achievements.ui." <> key, %{})
end
