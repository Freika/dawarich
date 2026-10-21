defmodule DawarichWeb.NativeAchievementDetail do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  alias DawarichWeb.{
    NativeAchievementNavigation,
    NativeAchievementParts,
    NativeAchievementCollection
  }

  def detail(assigns) do
    v = assigns.data.view

    assigns =
      assign(assigns,
        view: v,
        set: v.set,
        collection: s(assigns.locale, if(v.level == "country", do: "countries", else: "regions"))
      )

    ~H"""
    <nav class="breadcrumbs text-sm mb-3" aria-label={s(@locale, "breadcrumb")}>
      <ul>
        <li><.link patch="/achievements">{s(@locale, "title")}</.link></li><li :if={
          @set["parent_key"]
        }>
          <.link patch={"/achievements/" <> @set["parent_key"]}>{@view.continent}</.link>
        </li><li aria-current="page">{@set["place"]}</li>
      </ul>
    </nav>
    <div class="ach-layout">
      <NativeAchievementNavigation.sidebar view={@view} locale={@locale} />
      <div class="ach-main">
        <div class="ach-set-header">
          <DawarichWeb.ListParts.page_header title={@set["name"]}>
            <a href="#collection" class="btn btn-sm btn-ghost ach-collection-jump">{s(
              @locale,
              "browse_children",
              %{collection: String.downcase(@collection)}
            )}<.icon name="chevron-down" class="w-4 h-4" aria_hidden /></a>
            <.share_form set={@set} locale={@locale} enabled={true} />
            <.share_form set={@set} locale={@locale} enabled={false} />
            <a
              href={
                if @set["sharing_enabled"],
                  do: "/shared/achievements/" <> @set["sharing_uuid"],
                  else: "#"
              }
              class="btn btn-sm btn-outline"
              hidden={if !@set["sharing_enabled"], do: "hidden"}
            ><.icon name="external-link" class="w-4 h-4" aria_hidden />{s(@locale, "public_link")}</a>
          </DawarichWeb.ListParts.page_header>
        </div>
        <div class="ach-set-layout">
          <section class="ach-set-hero" aria-label={@set["name"]}>
            <div class="ach-set-details">
              <p class="ach-progress-summary">
                {s(
                  @locale,
                  if(@view.level == "country", do: "countries_progress", else: "regions_progress"),
                  %{count: min(@set["count"], @set["target"]), total: @set["target"]}
                )}
              </p>
              <progress
                class="progress progress-primary"
                value={@set["percent"]}
                max="100"
                aria-label={s(@locale, "collection_progress", %{collection: @collection})}
              >{@set["percent"]}%</progress>
              <p class="ach-muted ach-progress-caption">{caption(@set, @view, @locale)}</p>
              <p class="ach-muted ach-threshold-note">
                {s(@locale, "threshold_note", %{count: @data.threshold})}
              </p>
            </div>
            <figure class="ach-set-preview">
              <NativeAchievementParts.interactive_card
                item={NativeAchievementParts.item(@set)}
                locale={@locale}
              />
              <figcaption class="ach-preview-hint">{s(@locale, "preview_hint")}</figcaption>
            </figure>
          </section>
          <NativeAchievementCollection.collection
            data={@data}
            locale={@locale}
            collection={@collection}
          />
        </div>
        <DawarichWeb.AchievementModal.attribution locale={@locale} />
      </div>
    </div>
    """
  end

  def share_form(assigns) do
    ~H"""
    <form
      method="post"
      class="button_to"
      action={"/achievements/" <> @set["key"] <> "/toggle_sharing"}
      hidden={if @set["sharing_enabled"] == @enabled, do: "hidden"}
      phx-submit="share_collection"
    >
      <input type="hidden" name="_method" value="patch" />
      <button
        class={if @enabled, do: "btn btn-sm btn-primary", else: "btn btn-sm btn-ghost"}
        type="submit"
      ><.icon name={if @enabled, do: "share", else: "lock"} class="w-4 h-4" aria_hidden />{s(
        @locale,
        if(@enabled, do: "enable_sharing", else: "disable_sharing")
      )}</button>
      <input type="hidden" name="authenticity_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="enabled" value={to_string(@enabled)} />
    </form>
    """
  end

  defp caption(%{"completed" => true}, view, locale),
    do:
      s(locale, "completed_on", %{
        date: DawarichWeb.LocalizedDate.l(locale, view.completed_on, "long")
      })

  defp caption(set, _, locale),
    do: s(locale, "remaining", %{count: max(0, set["target"] - set["count"])})

  defp s(locale, key, bindings \\ %{}), do: t(locale, "achievements.ui." <> key, bindings)
end
