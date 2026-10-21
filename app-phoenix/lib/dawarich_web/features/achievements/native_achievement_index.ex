defmodule DawarichWeb.NativeAchievementIndex do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.{AchievementCard, NativeAchievementNavigation, NativeAchievementParts}

  def index(assigns) do
    ~H"""
    <DawarichWeb.ListParts.page_header title={s(@locale, "title")} />
    <div class="ach-layout">
      <NativeAchievementNavigation.sidebar view={@data.view} locale={@locale} />
      <div class="ach-main">
        <dl class="ach-stats" aria-label={s(@locale, "summary")}>
          <div class="ach-stat">
            <dt class="ach-stat-label">{s(@locale, "countries")}</dt><dd class="ach-stat-value">
              {@data.view.summary.earned_countries}<span class="ach-stat-total">/{@data.view.summary.total_countries}</span>
            </dd>
          </div>
          <div class="ach-stat">
            <dt class="ach-stat-label">{s(@locale, "regions")}</dt><dd class="ach-stat-value">
              {@data.view.summary.earned_subdivisions}<span class="ach-stat-total">/{DawarichWeb.NumberFormat.delimited(
                @locale,
                @data.view.summary.total_subdivisions
              )}</span>
            </dd>
          </div>
          <div class="ach-stat">
            <dt class="ach-stat-label">{s(@locale, "world_explored")}</dt><dd class="ach-stat-value">
              {@data.view.summary.percent}<span class="ach-stat-total">%</span>
            </dd>
          </div>
        </dl>
        <div
          :if={
            @data.view.summary.earned_countries == 0 and @data.view.summary.earned_subdivisions == 0
          }
          class="ach-getting-started"
        >
          <.icon name="compass" class="w-5 h-5" aria_hidden /><p>
            {s(@locale, "getting_started")}
            <a href="/imports/new" class="link link-hover">{s(@locale, "import_data")}</a>
          </p>
        </div>
        <section aria-labelledby="collection-heading">
          <div class="ach-section-heading">
            <div>
              <h2 id="collection-heading">{s(@locale, "continents")}</h2><p>
                {s(@locale, "collection_hint")}
              </p>
            </div>
          </div>
          <div class="ach-grid" data-testid="achievement-collection">
            <.link
              :for={set <- @data.view.sets}
              patch={"/achievements/" <> set["key"]}
              class="ach-card-link"
            ><AchievementCard.card
              card={set["card"]}
              locale={@locale}
              celebrate={set["celebrate"]}
              native
            /></.link>
            <NativeAchievementParts.interactive_card
              :for={set <- @data.view.orphans}
              item={NativeAchievementParts.item(set)}
              locale={@locale}
            />
          </div>
        </section>
        <DawarichWeb.AchievementModal.attribution locale={@locale} />
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "achievements.ui." <> key, %{})
end
