defmodule DawarichWeb.AchievementCard do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  attr :card, :map, required: true
  attr :locale, :string, required: true
  attr :small, :boolean, default: false
  attr :celebrate, :boolean, default: false
  attr :modal, :boolean, default: false
  attr :share, :map, default: nil

  def card(assigns) do
    c = assigns.card

    status =
      c["earned_label"] ||
        t(
          assigns.locale,
          "achievements.cards.status." <>
            cond do
              c["locked"] -> "locked"
              c["completed"] -> "unlocked"
              true -> "in_progress"
            end,
          %{}
        )

    metric =
      c["metric_label"] ||
        cond do
          c["completed"] ->
            t(assigns.locale, "achievements.cards.metric.explored", %{})

          c["locked"] ->
            t(assigns.locale, "achievements.cards.metric.not_yet_explored", %{})

          true ->
            t(assigns.locale, "achievements.cards.metric.percent_explored", %{
              percent: c["percent"]
            })
        end

    status =
      if(status == metric and not c["completed"] and not c["locked"],
        do: t(assigns.locale, "achievements.cards.status.in_progress", %{}),
        else: status
      )

    rarity = t(assigns.locale, "achievements.cards.rarity." <> String.downcase(c["rarity"]), %{})

    actions =
      if(c["locked"],
        do: "",
        else: "pointermove->achievement-card#move pointerleave->achievement-card#leave"
      ) <>
        if(assigns.modal, do: " click->card-modal#open keydown->card-modal#openOnKey", else: "")

    assigns = assign(assigns, status: status, metric: metric, rarity: rarity, actions: actions)

    ~H"""
    <div
      class={[
        "ach-card-wrap ach-spectral-wrap",
        @celebrate && "ach-card-wrap--celebrate",
        @small && "ach-spectral-wrap--sm",
        @modal && "ach-card-wrap--expandable"
      ]}
      data-controller="achievement-card"
      data-achievement-card-locked-value={to_string(@card["locked"])}
      data-achievement-card-key-value={@card["geography_key"] || @card["place"] || @card["name"]}
      data-achievement-card-rarity-value={@card["rarity"]}
      data-achievement-card-paper-value={asset("achievements/paper-pressed-fiber-v2.webp")}
      data-achievement-card-foil-value={asset("achievements/foil-stamped-grain-v4.webp")}
      data-action={@actions}
      role={@modal && "button"}
      tabindex={@modal && "0"}
      aria-label={
        @modal && t(@locale, "achievements.cards.open_label", %{name: @card["name"], status: @status})
      }
      data-share-key={@share && @share["key"]}
      data-share-shared={@share && to_string(@share["shared"])}
      data-share-toggle={@share && "/achievements/" <> @share["key"] <> "/toggle_sharing"}
      data-share-url={
        @share && @share["shared"] && @share["uuid"] && "/shared/achievements/" <> @share["uuid"]
      }
    >
      <article
        class={["ach-card ach-spectral", @card["locked"] && "ach-spectral--locked"]}
        aria-label={Enum.join([@card["name"], @rarity, @metric, @status], ", ")}
      >
        <div class="card-light" aria-hidden="true"></div>
        <div class="spectral-material" data-achievement-card-target="material" aria-hidden="true">
          <%= if @card["silhouette"] do %>
            <div class="geo-stage spectral-fallback">
              <svg
                viewBox={@card["silhouette"]["viewbox"]}
                preserveAspectRatio="xMidYMid meet"
                class="ach-silhouette-svg"
                aria-hidden="true"
              ><path d={@card["silhouette"]["path"]}></path></svg>
            </div>
          <% else %>
            <div class="spectral-unavailable">
              <.icon name="globe" class="size-6" /><span>{t(
                @locale,
                "achievements.cards.boundary_unavailable",
                %{}
              )}</span>
            </div>
          <% end %>
        </div>
        <div class="card-copy">
          <h2 class="card-title">{@card["name"]}</h2>
          <p :if={@card["description"] not in [nil, ""]} class="card-description">
            {@card["description"]}
          </p>
          <div class="meta-row">
            <div class="metric"><.icon name="map-pin" class="size-6" /><span>{@metric}</span></div><span
              class="meta-divider"
              aria-hidden="true"
            ></span>
            <div class="earned">
              <.icon
                name={
                  cond do
                    @card["locked"] -> "lock"
                    @card["completed"] -> "calendar"
                    true -> "clock"
                  end
                }
                class="size-6"
              /><span>{@status}</span>
            </div>
          </div>
          <div
            :if={!@card["locked"] and !@card["completed"] and @card["percent"] > 0}
            class="spectral-progress"
            role="progressbar"
            aria-label={t(@locale, "achievements.cards.progress_label", %{})}
            aria-valuenow={@card["percent"]}
            aria-valuemin="0"
            aria-valuemax="100"
          >
            <span style={"width: #{max(0,min(100,@card["percent"]))}%"}></span>
          </div>
          <div class="rarity-row">
            <span class="rarity">{@rarity}</span><span class="rarity-rule" aria-hidden="true"><i></i></span>
          </div><div class="wordmark">DAWARICH</div>
        </div>
      </article>
    </div>
    """
  end

  defp asset(path), do: DawarichWeb.Assets.stylesheet_path(path)
end
