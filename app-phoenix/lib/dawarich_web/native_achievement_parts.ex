defmodule DawarichWeb.NativeAchievementParts do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS
  alias DawarichWeb.AchievementCard
  attr :data, :any, required: true
  attr :selected, :any, required: true
  attr :share_url, :any, required: true
  attr :base_url, :string, required: true
  attr :locale, :string, required: true

  def page(assigns) do
    assigns = assign(assigns, :cards, if(assigns.data, do: cards(assigns.data), else: []))

    ~H"""
    <main id="native-achievements" class="my-5 min-w-0 ach-page">
      <%= if @data do %>
        <nav
          class="flex flex-wrap min-w-0 gap-2 mb-4"
          aria-label={t(@locale, "achievements.ui.collection_navigation", %{})}
        >
          <.link patch="/achievements">{t(@locale, "achievements.ui.summary", %{})}</.link>
          <.link
            :for={set <- @data.view.continents}
            patch={"/achievements/" <> set["key"]}
            class="break-words"
          >{set["place"]} {min(set["count"], set["target"])}/{set["target"]}</.link>
        </nav>
        <%= if @data.view[:set] do %>
          <h1 class="text-3xl font-bold break-words">{@data.view.set["name"]}</h1>
          <p class="ach-threshold-note break-words">
            {t(@locale, "achievements.ui.threshold_note", %{count: @data.threshold})}
          </p>
          <p class="ach-progress-summary">
            {t(
              @locale,
              "achievements.ui." <>
                if(@data.view.level == "country", do: "countries_progress", else: "regions_progress"),
              %{count: @data.view.set["count"], total: @data.view.set["target"]}
            )}
          </p>
          <form
            id="achievement-filter"
            phx-submit="filter"
            class="flex flex-wrap gap-2 min-w-0 my-4"
            role="search"
          >
            <label for="achievement-query">{t(@locale, "achievements.ui.search_children", %{
              collection: t(@locale, "achievements.ui.countries", %{})
            })}</label>
            <input
              id="achievement-query"
              name="q"
              type="search"
              value={@data.view.query}
              maxlength="100"
              class="input min-w-0 max-w-full"
            />
            <label for="achievement-status">{t(@locale, "achievements.ui.card_status", %{})}</label>
            <select id="achievement-status" name="status" class="select max-w-full">
              <option
                :for={status <- ~w(all unlocked in_progress locked)}
                value={status}
                selected={status == @data.view.status}
              >
                {t(@locale, "achievements.ui.status." <> status, %{})}
              </option>
            </select>
            <button class="btn whitespace-normal">{t(@locale, "achievements.ui.apply", %{})}</button>
            <.link patch={path(@data.query, %{"q" => "", "status" => "all"})}>{t(
              @locale,
              "achievements.ui.clear",
              %{}
            )}</.link>
          </form>
          <nav
            class="flex flex-wrap gap-2"
            aria-label={t(@locale, "achievements.ui.collection_pages", %{})}
          >
            <.link
              :if={@data.view.page > 1}
              rel="prev"
              patch={path(@data.query, %{"page" => @data.view.page - 1})}
            >{t(@locale, "achievements.ui.prev_page", %{})}</.link>
            <.link
              :if={@data.view.page < @data.view.pages}
              rel="next"
              patch={path(@data.query, %{"page" => @data.view.page + 1})}
            >{t(@locale, "achievements.ui.next_page", %{})}</.link>
          </nav>
          <p :if={@data.view.children == []} role="status">
            {t(@locale, "achievements.ui.no_results", %{})}
          </p>
        <% else %>
          <h1 class="text-3xl font-bold">{t(@locale, "achievements.ui.title", %{})}</h1>
          <dl class="flex flex-wrap gap-4">
            <div>
              <dt>{t(@locale, "achievements.ui.countries", %{})}</dt><dd>
                {@data.view.summary.earned_countries}/{@data.view.summary.total_countries}
              </dd>
            </div>
            <div>
              <dt>{t(@locale, "achievements.ui.regions", %{})}</dt><dd>
                {@data.view.summary.earned_subdivisions}/{@data.view.summary.total_subdivisions}
              </dd>
            </div>
            <div>
              <dt>{t(@locale, "achievements.ui.world_explored", %{})}</dt><dd>
                {@data.view.summary.percent}%
              </dd>
            </div>
          </dl>
          <p
            :if={
              @data.view.summary.earned_countries == 0 and @data.view.summary.earned_subdivisions == 0
            }
            class="ach-getting-started"
          >
            {t(@locale, "achievements.ui.getting_started", %{})}
            <a href="/imports/new">{t(@locale, "achievements.ui.import_data", %{})}</a>
          </p>
        <% end %>
        <div class="ach-grid min-w-0" data-testid="achievement-collection">
          <div :for={item <- @cards} class="min-w-0">
            <.link :if={item.route} patch={item.route} class="ach-card-link">{item.card["name"]}</.link>
            <button
              id={"achievement-" <> item.key}
              type="button"
              class="block w-full min-w-0 text-left"
              phx-click={
                JS.push_focus()
                |> JS.push("select_card", value: %{key: item.key})
                |> JS.dispatch("dawarich:open-dialog", to: "#achievement-dialog")
              }
              aria-label={
                t(@locale, "achievements.cards.open_label", %{
                  name: item.card["name"],
                  status: item.card["earned_label"] || ""
                })
              }
              data-celebrate={to_string(item.celebrate)}
            >
              <AchievementCard.card
                card={item.card}
                locale={@locale}
                celebrate={item.celebrate}
                native
              />
            </button>
          </div>
        </div>
        <DawarichWeb.AchievementModal.attribution locale={@locale} />
      <% end %>
      <dialog
        id="achievement-dialog"
        class="modal"
        aria-label={t(@locale, "achievements.modal.detail", %{})}
        phx-window-keydown={close()}
        phx-key="Escape"
      >
        <div class="modal-box min-w-0" style="overflow-wrap:anywhere">
          <div :if={@selected} data-selected-key={@selected.key}>
            <AchievementCard.card card={@selected.card} locale={@locale} native />
            <div :if={@selected.share_key} class="flex flex-wrap gap-2 mt-4">
              <button class="btn whitespace-normal" phx-click="share_card" phx-value-enabled="true">{t(
                @locale,
                "achievements.modal.share",
                %{}
              )}</button>
              <button class="btn whitespace-normal" phx-click="share_card" phx-value-enabled="false">{t(
                @locale,
                "achievements.modal.stop_sharing",
                %{}
              )}</button>
            </div>
            <div :if={@share_url} class="min-w-0">
              <label for="achievement-share-output">{t(@locale, "achievements.modal.public_link", %{})}</label>
              <input
                id="achievement-share-output"
                value={@share_url}
                readonly
                class="input w-full min-w-0"
              />
              <button
                id="achievement-copy"
                phx-hook="Clipboard"
                data-clipboard-text={@share_url}
                data-status-id="achievement-copy-status"
                data-copied-label={t(@locale, "achievements.modal.copied", %{})}
                data-failed-label={t(@locale, "achievements.modal.copy_error", %{})}
                class="btn"
              >{t(@locale, "achievements.modal.copy", %{})}</button>
              <label for="achievement-embed-output">{t(@locale, "achievements.modal.embed_code", %{})}</label>
              <textarea id="achievement-embed-output" readonly class="textarea w-full">{embed(@share_url, @locale, @base_url)}</textarea>
              <button
                id="achievement-embed-copy"
                phx-hook="Clipboard"
                data-clipboard-text={embed(@share_url, @locale, @base_url)}
                data-status-id="achievement-copy-status"
                data-copied-label={t(@locale, "achievements.modal.copied", %{})}
                data-failed-label={t(@locale, "achievements.modal.copy_error", %{})}
                class="btn"
              >{t(@locale, "achievements.modal.copy", %{})}</button>
              <p id="achievement-copy-status" role="status"></p>
            </div>
          </div>
          <button id="close-achievement-card" class="btn mt-3" phx-click={close()}>{t(
            @locale,
            "achievements.modal.close",
            %{}
          )}</button>
        </div>
        <button
          class="modal-backdrop"
          aria-label={t(@locale, "achievements.modal.close", %{})}
          phx-click={close()}
        ></button>
      </dialog>
    </main>
    """
  end

  def close,
    do:
      JS.push("close_card")
      |> JS.dispatch("dawarich:close-dialog", to: "#achievement-dialog")
      |> JS.pop_focus()

  def path(query, extra) do
    key = query["key"]
    base = if key, do: "/achievements/" <> key, else: "/achievements"
    values = query |> Map.drop(~w(key page)) |> Map.merge(extra)
    base <> "?" <> URI.encode_query(values)
  end

  def cards(data) do
    view = data.view
    sets = if view[:set], do: [view.set], else: view.sets ++ view.orphans

    Enum.map(sets, fn set ->
      %{
        key: set["key"],
        card: set["card"],
        route:
          if(set["parent_key"] || set["key"] in Enum.map(view.continents, & &1["key"]),
            do: "/achievements/" <> set["key"]
          ),
        share_key: set["key"],
        shared: set["sharing_enabled"],
        uuid: set["sharing_uuid"],
        celebrate: set["celebrate"]
      }
    end) ++
      Enum.map(view[:children] || [], fn card ->
        %{
          key: card["share_key"] || card["code"],
          card: card,
          route: card["key"] && "/achievements/" <> card["key"],
          share_key: card["share_key"],
          shared: card["share"] && card["share"]["shared"],
          uuid: card["share"] && card["share"]["uuid"],
          celebrate: false
        }
      end)
  end

  defp embed(url, locale, base_url),
    do:
      ~s(<iframe src="#{base_url}#{url}?embed=1" title="#{t(locale, "achievements.modal.iframe_title", %{})}" width="400" height="600" loading="lazy"></iframe>)
end
