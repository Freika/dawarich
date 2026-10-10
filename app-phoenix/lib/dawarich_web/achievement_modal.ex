defmodule DawarichWeb.AchievementModal do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  attr :locale, :string, required: true

  def modal(assigns) do
    ~H"""
    <dialog
      class="ach-modal"
      data-card-modal-target="dialog"
      data-action="close->card-modal#restore click->card-modal#backdrop"
      aria-label={t(@locale, "achievements.modal.detail", %{})}
    >
      <button
        type="button"
        class="ach-modal-close btn btn-circle"
        data-action="click->card-modal#close"
        aria-label={t(@locale, "achievements.modal.close", %{})}
      ><.icon name="x" class="w-5 h-5" aria_hidden /></button>
      <div class="ach-modal-stage" data-card-modal-target="stage"></div>
      <div class="ach-modal-tools" data-card-modal-target="tools" hidden>
        <button
          type="button"
          class="btn btn-sm btn-primary"
          data-action="click->card-modal#share"
          data-card-modal-target="sharingButton"
        >{t(@locale, "achievements.modal.share", %{})}</button><button
          type="button"
          class="btn btn-sm"
          data-action="click->card-modal#embed"
          data-card-modal-target="sharingButton"
        >{t(@locale, "achievements.modal.embed", %{})}</button>
      </div>
      <div class="ach-modal-panel" data-card-modal-target="panel" hidden>
        <label
          for="achievement-share-output"
          class="ach-modal-panel-label"
          data-card-modal-target="panelLabel"
        ></label>
        <div class="ach-modal-copyrow">
          <input
            id="achievement-share-output"
            type="text"
            readonly
            class="ach-modal-output input input-bordered input-sm"
            data-card-modal-target="output"
          /><button
            type="button"
            class="btn btn-sm btn-primary"
            data-action="click->card-modal#copy"
            data-card-modal-target="copyBtn"
          >{t(@locale, "achievements.modal.copy", %{})}</button>
        </div>
        <button
          type="button"
          class="ach-modal-unshare"
          data-action="click->card-modal#unshare"
          data-card-modal-target="unshareBtn sharingButton"
          hidden
        >{t(@locale, "achievements.modal.stop_sharing", %{})}</button>
      </div>
      <div class="ach-modal-error" data-card-modal-target="error" role="alert" hidden></div>
    </dialog>
    """
  end

  def labels(locale) do
    pairs =
      for key <- ~w(public_link embed_code iframe_title copy copied share_error copy_error),
          do: {key, t(locale, "achievements.modal." <> key, %{})}

    {:object, pairs}
    |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
    |> IO.iodata_to_binary()
  end

  attr :locale, :string, required: true

  def attribution(assigns) do
    ~H"""
    <details class="ach-attribution">
      <summary>{t(@locale, "achievements.ui.about_boundaries", %{})}</summary><p>
        {t(@locale, "achievements.ui.boundaries_note", %{})}
        <a href="https://www.naturalearthdata.com" target="_blank" rel="noopener" class="link">Natural Earth</a>
        (public domain),
        <a href="https://www.geoboundaries.org" target="_blank" rel="noopener" class="link">geoBoundaries</a>
        (CC BY 4.0).
      </p>
    </details>
    """
  end
end
