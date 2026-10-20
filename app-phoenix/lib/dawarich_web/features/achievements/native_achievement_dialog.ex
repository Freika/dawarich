defmodule DawarichWeb.NativeAchievementDialog do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.NativeAchievementParts

  def dialog(assigns) do
    assigns = assign_new(assigns, :panel, fn -> nil end)
    assigns = assign(assigns, :output, output(assigns))

    ~H"""
    <dialog
      id="native-achievement-dialog"
      class="ach-modal"
      aria-label={s(@locale, "detail")}
      phx-window-keydown={NativeAchievementParts.close()}
      phx-key="Escape"
    >
      <button
        id="native-close-achievement-card"
        type="button"
        class="ach-modal-close btn btn-circle"
        phx-click={NativeAchievementParts.close()}
        aria-label={s(@locale, "close")}
      ><.icon name="x" class="w-5 h-5" aria_hidden /></button>
      <div class="ach-modal-stage">
        <div :if={@selected} data-selected-key={@selected.key}>
          <DawarichWeb.AchievementCard.card card={@selected.card} locale={@locale} native />
        </div>
      </div>
      <div class="ach-modal-tools" hidden={!(@selected && @selected.share_key)}>
        <button
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="share_card"
          phx-value-enabled="true"
          phx-value-panel="link"
        >{s(@locale, "share")}</button>
        <button
          type="button"
          class="btn btn-sm"
          phx-click="share_card"
          phx-value-enabled="true"
          phx-value-panel="embed"
        >{s(@locale, "embed")}</button>
      </div>
      <div class="ach-modal-panel" hidden={is_nil(@share_url) or is_nil(@panel)}>
        <label for="achievement-share-output" class="ach-modal-panel-label">{if @share_url,
          do: s(@locale, if(@panel == "embed", do: "embed_code", else: "public_link"))}</label>
        <div class="ach-modal-copyrow">
          <input
            id="achievement-share-output"
            type="text"
            readonly
            class="ach-modal-output input input-bordered input-sm"
            value={@output}
          />
          <button
            id="native-achievement-copy"
            type="button"
            class="btn btn-sm btn-primary"
            phx-hook="AchievementClipboard"
            data-native-clipboard-text={@output}
            data-native-copied-label={s(@locale, "copied")}
            data-native-failed-label={s(@locale, "copy_error")}
          >{s(@locale, "copy")}</button>
        </div>
        <button
          type="button"
          class="ach-modal-unshare"
          phx-click="share_card"
          phx-value-enabled="false"
          hidden={is_nil(@share_url) or is_nil(@panel)}
        >{s(@locale, "stop_sharing")}</button>
      </div>
      <div class="ach-modal-error" role="alert" hidden></div>
    </dialog>
    """
  end

  defp output(%{share_url: nil}), do: nil

  defp output(%{panel: "embed"} = a),
    do:
      ~s(<iframe src="#{a.base_url}#{a.share_url}?embed=1" title="#{s(a.locale, "iframe_title")}" width="400" height="600" loading="lazy"></iframe>)

  defp output(a), do: a.base_url <> a.share_url
  defp s(locale, key), do: t(locale, "achievements.modal." <> key, %{})
end
