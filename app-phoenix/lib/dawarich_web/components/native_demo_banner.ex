defmodule DawarichWeb.NativeDemoBanner do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon
  alias Phoenix.LiveView.JS

  attr :locale, :string, required: true
  attr :target, :any, default: nil
  attr :removing, :boolean, default: false

  def banner(assigns) do
    ~H"""
    <div
      id="demo-data-banner"
      class="fixed bottom-0 left-1/2 -translate-x-1/2 z-30 mb-[calc(1rem+env(safe-area-inset-bottom))] max-w-[calc(100vw-2rem)]"
    >
      <div class="alert alert-info shadow-lg py-1.5 px-3 flex flex-wrap items-center gap-1.5 rounded-lg text-sm">
        <span class="font-medium min-w-0">{t(@locale, "layouts.map.you_re_viewing_demo_data", %{})}</span>
        <span :if={@removing} class="loading loading-spinner loading-xs text-info"></span>
        <button
          id="native-demo-remove"
          type="button"
          class="btn btn-error btn-xs"
          disabled={@removing}
          phx-click="demo:remove"
          phx-target={@target}
          data-confirm={t(@locale, "javascript.demo.confirm_delete", %{})}
        >
          {t(@locale, "layouts.map.delete", %{})}
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          aria-label={t(@locale, "map.onboarding_modal.close", %{})}
          phx-click={JS.hide(to: "#demo-data-banner")}
        >
          <Icon.icon name="x" class="w-3 h-3" />
        </button>
      </div>
    </div>
    """
  end
end
