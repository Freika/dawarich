defmodule DawarichWeb.AchievementIndex do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.{AchievementCard, AchievementSidebar, AchievementModal, Icon}
  attr :view, :map, required: true
  attr :locale, :string, required: true

  def page(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
      <h1 class="text-3xl font-bold">{t(@locale, "achievements.ui.title", %{})}</h1>
    </div>
    <div class="ach-layout">
      <.sidebar view={@view} locale={@locale} /><div class="ach-main">
        <dl class="ach-stats" aria-label={t(@locale, "achievements.ui.summary", %{})}>
          <div class="ach-stat">
            <dt class="ach-stat-label">{t(@locale, "achievements.ui.countries", %{})}</dt><dd class="ach-stat-value">
              {@view.summary.earned_countries}<span class="ach-stat-total">/{@view.summary.total_countries}</span>
            </dd>
          </div>
          <div class="ach-stat">
            <dt class="ach-stat-label">{t(@locale, "achievements.ui.regions", %{})}</dt><dd class="ach-stat-value">
              {@view.summary.earned_subdivisions}<span class="ach-stat-total">/{DawarichWeb.NumberFormat.delimited(
                @locale,
                @view.summary.total_subdivisions
              )}</span>
            </dd>
          </div>
          <div class="ach-stat">
            <dt class="ach-stat-label">{t(@locale, "achievements.ui.world_explored", %{})}</dt><dd class="ach-stat-value">
              {@view.summary.percent}<span class="ach-stat-total">%</span>
            </dd>
          </div>
        </dl>
        <div
          :if={@view.summary.earned_countries == 0 and @view.summary.earned_subdivisions == 0}
          class="ach-getting-started"
        >
          <.icon name="compass" class="w-5 h-5" aria_hidden /><p>
            {t(@locale, "achievements.ui.getting_started", %{})}
            <a href="/imports/new" class="link link-hover">{t(
              @locale,
              "achievements.ui.import_data",
              %{}
            )}</a>
          </p>
        </div>
        <section aria-labelledby="collection-heading">
          <div class="ach-section-heading">
            <div>
              <h2 id="collection-heading">{t(@locale, "achievements.ui.continents", %{})}</h2><p>
                {t(@locale, "achievements.ui.collection_hint", %{})}
              </p>
            </div>
          </div>
          <div class="ach-grid" data-testid="achievement-collection">
            <a :for={set <- @view.sets} href={"/achievements/"<>set["key"]} class="ach-card-link"><.card
              card={set["card"]}
              locale={@locale}
              celebrate={set["celebrate"]}
            /></a>
            <.card
              :for={set <- @view.orphans}
              card={set["card"]}
              locale={@locale}
              celebrate={set["celebrate"]}
              modal
              share={
                %{
                  "key" => set["key"],
                  "shared" => set["sharing_enabled"],
                  "uuid" => set["sharing_uuid"]
                }
              }
            />
          </div>
        </section><.attribution locale={@locale} />
      </div>
    </div>
    """
  end
end
