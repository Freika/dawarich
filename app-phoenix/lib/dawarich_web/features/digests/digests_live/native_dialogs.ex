defmodule DawarichWeb.DigestsLive.NativeDialogs do
  @moduledoc false
  use DawarichWeb, :html
  attr :dialog, :any, required: true
  attr :data, :any, required: true
  attr :share, :any, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    ~H"""
    <section
      :if={@dialog == :delete}
      id="digest-delete-dialog"
      phx-window-keydown="cancel_delete"
      phx-key="Escape"
      role="dialog"
      aria-modal="true"
      aria-labelledby="digest-delete-title"
      class="card bg-base-200 min-w-0 p-4"
    >
      <h2 id="digest-delete-title" class="break-words">
        {t(@locale, "users.digests.show.are_you_sure_you_want_to_delete_the_year_digest", %{
          year: @data.year
        })}
      </h2>
      <div class="flex flex-wrap gap-2">
        <button class="btn whitespace-normal" phx-click="confirm_delete">{t(
          @locale,
          "users.digests.show.delete",
          %{}
        )}</button>
        <button class="btn whitespace-normal" phx-click="cancel_delete">{t(
          @locale,
          "javascript.common.cancel",
          %{}
        )}</button>
      </div>
    </section>
    <section
      :if={@dialog == :share}
      id="digest-share-dialog"
      phx-window-keydown="close_share"
      phx-key="Escape"
      role="dialog"
      aria-modal="true"
      aria-labelledby="digest-share-title"
      class="card bg-base-200 min-w-0 p-4"
    >
      <h2 id="digest-share-title">{t(@locale, "users.digests.show.sharing_settings", %{})}</h2>
      <form
        id="digest-share-form"
        phx-submit="share"
        phx-change="share"
        class="flex flex-wrap min-w-0 gap-2"
      >
        <input type="hidden" name="share[enabled]" value="0" />
        <label for="digest-sharing-enabled">{t(
          @locale,
          "users.digests.show.enable_public_access",
          %{}
        )}</label>
        <input
          id="digest-sharing-enabled"
          type="checkbox"
          name="share[enabled]"
          value="1"
          checked={@share.enabled}
        />
        <label for="digest-sharing-expiration">{t(
          @locale,
          "users.digests.show.link_expiration",
          %{}
        )}</label>
        <select id="digest-sharing-expiration" name="share[expiration]" class="select max-w-full">
          <option
            :for={{label, expiry} <- [{"1 hour", "1h"}, {"12 hours", "12h"}, {"24 hours", "24h"}]}
            value={expiry}
            selected={expiry == @share.expiration}
          >
            {label}
          </option>
        </select>
        <button class="btn whitespace-normal" type="submit">{t(@locale, "javascript.common.save", %{})}</button>
      </form>
      <p class="break-words">{t(@locale, "users.digests.show.privacy_protection", %{})}</p>
      <p class="break-words">{t(@locale, "users.digests.show.exact_coordinates_are_hidden", %{})}</p>
      <p class="break-words">
        {t(@locale, "users.digests.show.personal_information_is_not_included", %{})}
      </p>
      <a :if={@share.url != ""} href={@share.url} class="break-all">{@share.url}</a>
      <button class="btn whitespace-normal" phx-click="close_share">{t(
        @locale,
        "javascript.common.close",
        %{}
      )}</button>
    </section>
    """
  end
end
