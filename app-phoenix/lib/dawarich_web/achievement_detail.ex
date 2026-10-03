defmodule DawarichWeb.AchievementDetail do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.{
    AchievementSidebar,
    AchievementCard,
    AchievementModal,
    AchievementSharingControls,
    AchievementChildren,
    Icon
  }

  attr :view, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :threshold, :integer, required: true
  attr :query, :map, required: true

  def page(assigns) do
    label =
      t(
        assigns.locale,
        "achievements.ui." <>
          if(assigns.view.level == "country", do: "countries", else: "regions"),
        %{}
      )

    assigns = assign(assigns, :label, label)

    ~H"""
    <nav class="breadcrumbs text-sm mb-3" aria-label={t(@locale, "achievements.ui.breadcrumb", %{})}>
      <ul>
        <li><a href="/achievements">{t(@locale, "achievements.ui.title", %{})}</a></li><li :if={
          @view.set["parent_key"]
        }>
          <a href={"/achievements/"<>@view.set["parent_key"]}>{@view.continent}</a>
        </li><li aria-current="page">{@view.set["place"]}</li>
      </ul>
    </nav>
    <div class="ach-layout">
      <.sidebar view={@view} locale={@locale} /><div class="ach-main">
        <div class="ach-set-header">
          <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
            <h1 class="text-3xl font-bold">{@view.set["name"]}</h1><div class="flex flex-wrap gap-2">
              <a
                href="#collection"
                class="btn btn-sm btn-ghost ach-collection-jump"
                data-turbo="false"
              >{t(@locale, "achievements.ui.browse_children", %{collection: String.downcase(@label)})}<.icon
                name="chevron-down"
                class="w-4 h-4"
                aria_hidden
              /></a>
              <.controls set={@view.set} locale={@locale} csrf={@csrf} />
            </div>
          </div>
        </div>
        <div class="ach-set-layout">
          <section class="ach-set-hero" aria-label={@view.set["name"]}>
            <div class="ach-set-details">
              <p class="ach-progress-summary">
                {t(
                  @locale,
                  "achievements.ui." <>
                    if(@view.level == "country", do: "countries_progress", else: "regions_progress"),
                  %{count: min(@view.set["count"], @view.set["target"]), total: @view.set["target"]}
                )}
              </p>
              <progress
                class="progress progress-primary"
                value={@view.set["percent"]}
                max="100"
                aria-label={t(@locale, "achievements.ui.collection_progress", %{collection: @label})}
              >{@view.set["percent"]}%</progress>
              <p class="ach-muted ach-progress-caption">
                <%= if @view.set["completed"] do %>
                  {t(@locale, "achievements.ui.completed_on", %{
                    date: DawarichWeb.LocalizedDate.l(@locale, @view.completed_on, "long")
                  })}
                <% else %>
                  {t(@locale, "achievements.ui.remaining", %{
                    count: @view.set["target"] - min(@view.set["count"], @view.set["target"])
                  })}
                <% end %>
              </p>
              <p class="ach-muted ach-threshold-note">
                {t(@locale, "achievements.ui.threshold_note", %{count: @threshold})}
              </p>
            </div>
            <figure class="ach-set-preview" data-card-modal-target="featured">
              <.card
                card={@view.set["card"]}
                locale={@locale}
                celebrate={@view.set["celebrate"]}
                modal
                share={
                  %{
                    "key" => @view.set["key"],
                    "shared" => @view.set["sharing_enabled"],
                    "uuid" => @view.set["sharing_uuid"]
                  }
                }
              /><figcaption class="ach-preview-hint">
                {t(@locale, "achievements.ui.preview_hint", %{})}
              </figcaption>
            </figure>
          </section><.children view={@view} locale={@locale} query={@query} />
        </div><.attribution locale={@locale} />
      </div>
    </div>
    """
  end
end
