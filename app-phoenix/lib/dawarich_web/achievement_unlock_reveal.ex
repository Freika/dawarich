defmodule DawarichWeb.AchievementUnlockReveal do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.AchievementCard, only: [card: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.Achievements.UiText

  def render(card, count, locale) do
    reveal(%{card: card, count: count, locale: locale})
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  def reveal(assigns) do
    ~H"""
    <section
      class="ach-unlock-reveal"
      aria-label={UiText.t(@locale, "unlocks.announcement")}
      data-testid="achievement-unlock-deck"
    >
      <div class="ach-unlock-heading">
        <div>
          <span class="ach-unlock-kicker">{UiText.t(@locale, "unlocks.kicker")}</span>
          <h2>{UiText.t(@locale, "unlocks.announcement")}</h2>
        </div>
        <button
          type="button"
          class="ach-unlock-close"
          data-action="click->achievement-unlocks#dismiss"
          aria-label={UiText.t(@locale, "unlocks.dismiss")}
        ><.icon name="x" class="w-4 h-4" aria_hidden={true} /></button>
      </div>
      <div class={["ach-unlock-stack", @count > 1 && "ach-unlock-stack--multiple"]}>
        <div :if={@count > 1} class="ach-unlock-back ach-unlock-back--rear" aria-hidden="true"></div>
        <div :if={@count > 1} class="ach-unlock-back ach-unlock-back--middle" aria-hidden="true">
        </div>
        <a
          class="ach-unlock-front"
          aria-label={UiText.t(@locale, "unlocks.view", %{"name" => @card["name"]})}
          href={@card["path"]}
        >
          <.card card={@card["attributes"]} locale={@locale} small={true} />
        </a>
      </div>
      <div class="ach-unlock-footer">
        <span class="ach-unlock-count">{UiText.t(@locale, "unlocks.remaining", %{"count" => @count})}</span>
        <button
          type="button"
          class="ach-unlock-next"
          data-action="click->achievement-unlocks#nextCard"
        >
          {UiText.t(@locale, "unlocks." <> if(@count > 1, do: "next", else: "done"))}
          <.icon name="chevron-right" class="w-4 h-4" aria_hidden={true} />
        </button>
      </div>
    </section>
    """
  end
end
