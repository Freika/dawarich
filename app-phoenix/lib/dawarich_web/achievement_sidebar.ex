defmodule DawarichWeb.AchievementSidebar do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  attr :view, :map, required: true
  attr :locale, :string, required: true

  def sidebar(assigns) do
    active = assigns.view[:sidebar_key]

    name =
      Enum.find_value(assigns.view.continents, fn card ->
        if(card["key"] == active, do: card["place"])
      end) || t(assigns.locale, "achievements.ui.summary", %{})

    assigns = assign(assigns, active: active, name: name)

    ~H"""
    <aside class="ach-navigation">
      <nav
        class="ach-side ach-side--desktop"
        aria-label={t(@locale, "achievements.ui.collection_navigation", %{})}
      >
        <.links view={@view} locale={@locale} active={@active} />
      </nav>
      <details class="ach-mobile-nav">
        <summary>
          <span>{t(@locale, "achievements.ui.browse", %{})}</span>
          <strong>{@name}</strong><.icon name="chevron-down" class="w-4 h-4" aria_hidden />
        </summary>
        <nav class="ach-side" aria-label={t(@locale, "achievements.ui.collection_navigation", %{})}>
          <.links view={@view} locale={@locale} active={@active} />
        </nav>
      </details>
    </aside>
    """
  end

  attr :view, :map, required: true
  attr :locale, :string, required: true
  attr :active, :string, default: nil

  def links(assigns) do
    ~H"""
    <a
      href="/achievements"
      class={["ach-side-link", is_nil(@active) && "ach-side-link--active"]}
      aria-current={is_nil(@active) && "page"}
    ><span>{t(@locale, "achievements.ui.summary", %{})}</span><span class="ach-side-count">{@view.summary.earned_countries}/{@view.summary.total_countries}</span></a>
    <div class="ach-side-group">{t(@locale, "achievements.ui.continents", %{})}</div>
    <a
      :for={card <- @view.continents}
      href={"/achievements/"<>card["key"]}
      class={["ach-side-link", @active == card["key"] && "ach-side-link--active"]}
      aria-current={@active == card["key"] && "page"}
    >
      <span>{card["place"]}</span><span class="ach-side-count">{min(card["count"], card["target"])}/{card[
        "target"
      ]}</span><span class="ach-side-bar" aria-hidden="true"><span style={"width: #{card["percent"]}%;"}></span></span>
    </a>
    """
  end
end
