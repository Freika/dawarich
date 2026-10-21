defmodule DawarichWeb.NativeAchievementCollection do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.{AchievementCard, NativeAchievementParts}

  def collection(assigns) do
    v = assigns.data.view

    assigns =
      assign(assigns,
        view: v,
        cards: NativeAchievementParts.cards(assigns.data) |> tl(),
        statuses:
          ~w(all unlocked) ++
            if(v.level == "country", do: ["in_progress"], else: []) ++ ["locked"],
        search:
          s(assigns.locale, "search_children", %{collection: String.downcase(assigns.collection)})
      )

    ~H"""
    <section id="collection" aria-labelledby="collection-heading" tabindex="-1">
      <div class="ach-collection-header">
        <div class="ach-section-heading">
          <h2 id="collection-heading">
            {@collection} <span class="ach-muted">({@view.set["target"]})</span>
          </h2>
          <nav
            :if={@view.children != []}
            class="ach-collection-pager"
            aria-label={s(@locale, "collection_pages")}
          >
            <span class="ach-page-range ach-muted">{range(@view, @locale)}</span>
            <.link
              :for={{direction, page} <- pages(@view)}
              patch={pager(@view, page)}
              class="btn btn-sm btn-ghost"
              rel={direction}
              aria-label={s(@locale, direction <> "_page")}
            ><.icon
              name={if direction == "prev", do: "chevron-left", else: "chevron-right"}
              class="w-4 h-4"
              aria_hidden
            /></.link>
          </nav>
        </div>
        <form
          id="native-achievement-filter"
          class="ach-collection-toolbar"
          role="search"
          action={base(@view) <> "#collection"}
          accept-charset="UTF-8"
          method="get"
          phx-submit="filter"
        >
          <div class="ach-search-field">
            <label class="sr-only" for="q">{@search}</label><.icon
              name="search"
              class="w-4 h-4"
              aria_hidden
            /><input
              value={@view.query}
              placeholder={@search}
              maxlength="100"
              class="input input-bordered input-sm w-full"
              size="100"
              type="search"
              name="q"
              id="q"
            />
          </div>
          <div class="ach-status-field">
            <label class="sr-only" for="status">{s(@locale, "card_status")}</label><select
              class="select select-bordered select-sm w-full"
              name="status"
              id="status"
            ><option
              :for={status <- @statuses}
              selected={if @view.status == status, do: "selected"}
              value={status}
            >
              {s(@locale, "status." <> status)}
            </option></select>
          </div>
          <input type="submit" name="commit" value={s(@locale, "apply")} class="btn btn-sm" />
          <.link
            :if={String.trim(@view.query) != "" or @view.status != "all"}
            patch={base(@view) <> "#collection"}
            class="btn btn-sm btn-ghost"
          >{s(@locale, "clear")}</.link>
        </form>
      </div>
      <div class="ach-collection-content">
        <%= if @view.children != [] do %>
          <div class="ach-child-grid" data-testid="achievement-children">
            <%= for item <- @cards do %>
              <.link :if={item.route} patch={item.route} class="ach-card-link"><AchievementCard.card
                card={item.card}
                locale={@locale}
                small
                native
              /></.link>
              <NativeAchievementParts.interactive_card
                :if={!item.route}
                item={item}
                locale={@locale}
                small
              />
            <% end %>
          </div>
          <div class="ach-pagination">
            <p class="ach-muted text-sm">{range(@view, @locale)}</p><DawarichWeb.Paginator.paginator
              locale={@locale}
              path={base(@view)}
              query={@data.request_query}
              page={@view.page}
              total_pages={@view.pages}
              anchor="collection"
            />
          </div>
        <% else %>
          <div class="ach-empty" role="status">
            <.icon name="search" class="w-6 h-6" aria_hidden /><h3>{s(@locale, "no_results")}</h3><p>
              {s(@locale, "no_results_hint")}
            </p><.link patch={base(@view) <> "#collection"} class="btn btn-sm btn-outline">{s(
              @locale,
              "clear"
            )}</.link>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp range(v, locale),
    do:
      s(locale, "page_range", %{
        first: (v.page - 1) * 12 + 1,
        last: (v.page - 1) * 12 + length(v.children),
        total: DawarichWeb.NumberFormat.delimited(locale, v.total)
      })

  defp pages(v),
    do:
      if(v.page > 1, do: [{"prev", v.page - 1}], else: []) ++
        if(v.page < v.pages, do: [{"next", v.page + 1}], else: [])

  defp base(v), do: "/achievements/" <> v.set["key"]

  defp pager(v, page),
    do:
      base(v) <>
        "?" <>
        URI.encode_query(
          [{"page", page}] ++
            if(v.query != "", do: [{"q", v.query}], else: []) ++ [{"status", v.status}]
        ) <> "#collection"

  defp s(locale, key, bindings \\ %{}), do: t(locale, "achievements.ui." <> key, bindings)
end
