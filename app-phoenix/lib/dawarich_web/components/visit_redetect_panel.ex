defmodule DawarichWeb.VisitRedetectPanel do
  @moduledoc false
  use DawarichWeb, :html
  attr :locale, :string, required: true
  attr :cooldown, :boolean, required: true
  attr :restricted, :boolean, required: true
  attr :available_at, :string, default: nil
  attr :rails_csrf_token, :string, default: nil

  def panel(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h3 class="text-xl font-bold">{text(@locale, "re_run_detection_on_full_history")}</h3>
        <p class="text-sm opacity-80">
          {text(@locale, "replaces_all_suggested_visits_across_your_entire_history_with_fresh")}
        </p>
        <p :if={@restricted} class="text-xs opacity-70">
          {text(@locale, "on_the_lite_plan_re_detection_covers_your_visible_12")}
        </p>
        <form class="button_to" method="post" action="/visits/redetections">
          <button
            class={"btn btn-warning " <> if(@cooldown, do: "btn-disabled", else: "")}
            disabled={@cooldown}
            data-turbo-confirm={
              text(@locale, "replace_all_suggested_visits_across_your_full_history_confirmed_visits")
            }
            type="submit"
          >
            {text(@locale, "re_run_detection_on_full_history")}
          </button>
          <input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
        </form>
        <span :if={@cooldown} class="text-xs opacity-70">{text(@locale, "available_again_at")} {@available_at}.</span>
      </div>
    </div>
    """
  end

  defp text(locale, key), do: t(locale, "settings.visits.redetect_panel." <> key, %{})
end
