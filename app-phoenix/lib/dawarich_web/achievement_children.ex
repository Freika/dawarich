defmodule DawarichWeb.AchievementChildren do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.AchievementCard, only: [card: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.Paginator
  attr :view, :map, required: true
  attr :locale, :string, required: true
  attr :query, :map, required: true

  def children(assigns) do
    label =
      t(
        assigns.locale,
        "achievements.ui." <>
          if(assigns.view.level == "country", do: "countries", else: "regions"),
        %{}
      )

    assigns =
      assign(assigns,
        label: label,
        search_label:
          t(assigns.locale, "achievements.ui.search_children", %{
            collection: String.downcase(label)
          })
      )

    ~H"""
    <section id="collection" aria-labelledby="collection-heading" tabindex="-1">
      <div class="ach-collection-header">
        <div class="ach-section-heading">
          <h2 id="collection-heading">
            {@label} <span class="ach-muted">({@view.set["target"]})</span>
          </h2>
          <nav
            :if={@view.children != []}
            class="ach-collection-pager"
            aria-label={t(@locale, "achievements.ui.collection_pages", %{})}
          >
            <span class="ach-page-range ach-muted">{page_range(@view, @locale)}</span>
            <a
              :if={@view.page > 1}
              href={url(@view, @view.page - 1)}
              class="btn btn-sm btn-ghost"
              rel="prev"
              aria-label={t(@locale, "achievements.ui.prev_page", %{})}
            ><.icon name="chevron-left" class="w-4 h-4" aria_hidden /></a>
            <a
              :if={@view.page < @view.pages}
              href={url(@view, @view.page + 1)}
              class="btn btn-sm btn-ghost"
              rel="next"
              aria-label={t(@locale, "achievements.ui.next_page", %{})}
            ><.icon name="chevron-right" class="w-4 h-4" aria_hidden /></a>
          </nav>
        </div>
        <form
          class="ach-collection-toolbar"
          data-turbo="false"
          role="search"
          action={"/achievements/"<>@view.set["key"]<>"#collection"}
          accept-charset="UTF-8"
          method="get"
        >
          <div class="ach-search-field">
            <label class="sr-only" for="q">{@search_label}</label>
            <.icon name="search" class="w-4 h-4" aria_hidden />
            <input
              value={@view.query}
              placeholder={@search_label}
              maxlength="100"
              class="input input-bordered input-sm w-full"
              size="100"
              type="search"
              name="q"
              id="q"
              phx-update="ignore"
            />
          </div>
          <div class="ach-status-field">
            <label class="sr-only" for="status">{t(@locale, "achievements.ui.card_status", %{})}</label>
            <select
              class="select select-bordered select-sm w-full"
              name="status"
              id="status"
              phx-update="ignore"
            ><option
              :for={status <- statuses(@view.level)}
              selected={@view.status == status && "selected"}
              value={status}
            >
              {t(@locale, "achievements.ui.status." <> status, %{})}
            </option></select>
          </div>
          <input
            type="submit"
            name="commit"
            value={t(@locale, "achievements.ui.apply", %{})}
            class="btn btn-sm"
            data-disable-with={t(@locale, "achievements.ui.apply", %{})}
          />
          <a
            :if={present?(@view.query) or @view.status != "all"}
            class="btn btn-sm btn-ghost"
            href={clear_url(@view)}
          >{t(@locale, "achievements.ui.clear", %{})}</a>
        </form>
      </div>
      <div class="ach-collection-content">
        <%= if @view.children  !=  [] do %>
          <div class="ach-child-grid" data-testid="achievement-children">
            <%= for child <- @view.children do %>
              <%= if child["key"] do %>
                <a href={"/achievements/"<>child["key"]} class="ach-card-link"><.card
                  card={child}
                  locale={@locale}
                  small
                /></a>
              <% else %>
                <.card card={child} locale={@locale} small modal share={child["share"]} />
              <% end %>
            <% end %>
          </div>
          <div class="ach-pagination">
            <p class="ach-muted text-sm">{page_range(@view, @locale)}</p><Paginator.paginator
              locale={@locale}
              path={"/achievements/" <> @view.set["key"]}
              query={@query}
              page={@view.page}
              total_pages={@view.pages}
              anchor="collection"
              patch={false}
            />
          </div>
        <% else %>
          <div class="ach-empty" role="status">
            <.icon name="search" class="w-6 h-6" aria_hidden /><h3>
              {t(@locale, "achievements.ui.no_results", %{})}
            </h3><p>{t(@locale, "achievements.ui.no_results_hint", %{})}</p><a
              href={clear_url(@view)}
              class="btn btn-sm btn-outline"
            >{t(@locale, "achievements.ui.clear", %{})}</a>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp present?(value), do: String.trim(value) != ""
  defp statuses("country"), do: ~w(all unlocked in_progress locked)
  defp statuses(_), do: ~w(all unlocked locked)
  defp clear_url(view), do: "/achievements/" <> view.set["key"] <> "#collection"

  defp url(view, page) do
    query = %{"page" => page, "status" => view.status}
    query = if(present?(view.query), do: Map.put(query, "q", view.query), else: query)

    "/achievements/" <>
      view.set["key"] <> "?" <> DawarichWeb.Params.to_query(query) <> "#collection"
  end

  defp page_range(view, locale) do
    first = if(view.children == [], do: 0, else: (view.page - 1) * 12 + 1)
    last = if(view.children == [], do: 0, else: (view.page - 1) * 12 + length(view.children))

    t(locale, "achievements.ui.page_range", %{
      first: first,
      last: last,
      total: DawarichWeb.NumberFormat.delimited(locale, view.total)
    })
  end
end
