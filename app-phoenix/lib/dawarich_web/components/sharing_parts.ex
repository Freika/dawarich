defmodule DawarichWeb.SharingParts do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.Icon

  @expirations [
    {"1 hour", "1h"},
    {"12 hours", "12h"},
    {"24 hours", "24h"},
    {"1 week", "1w"},
    {"1 month", "1m"}
  ]

  attr :locale, :string, required: true
  attr :scope, :string, required: true
  attr :hint, :string, required: true
  attr :action, :string, required: true
  attr :enabled, :boolean, required: true
  attr :expiration, :string, required: true
  attr :url, :string, required: true
  attr :csrf, :string, default: nil
  attr :allowed, :boolean, default: true
  attr :upgrade, :string, default: ""

  def sharing_dialog(assigns) do
    assigns = assign(assigns, :expirations, @expirations)

    ~H"""
    <dialog id="sharing_modal" class="modal" phx-hook="RailsStimulus" phx-update="ignore">
      <div class="modal-box">
        <form method="dialog">
          <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2">✕</button>
        </form>
        <h3 class="font-bold text-lg mb-4 flex items-center gap-2">
          <Icon.icon name="link" class="size-6" /> {t(@locale, @scope <> ".sharing_settings", %{})}
        </h3>
        <%= if @allowed do %>
          <div data-controller="sharing-modal">
            <form
              data-sharing-modal-target="form"
              action={@action}
              accept-charset="UTF-8"
              method="post"
            >
              <input type="hidden" name="_method" value="patch" /><input
                :if={@csrf}
                type="hidden"
                name="authenticity_token"
                value={@csrf}
              />
              <div class="form-control mb-4">
                <label class="label cursor-pointer">
                  <span class="label-text font-medium">{t(
                    @locale,
                    @scope <> ".enable_public_access",
                    %{}
                  )}</span>
                  <input
                    type="checkbox"
                    name="enabled"
                    value="1"
                    checked={@enabled}
                    class="toggle toggle-primary"
                    data-action="change->sharing-modal#toggleSharing"
                    data-sharing-modal-target="enableToggle"
                  />
                </label>
                <div class="label">
                  <span class="label-text-alt text-gray-500">{t(@locale, @hint, %{})}</span>
                </div>
              </div>
              <div
                data-sharing-modal-target="expirationSettings"
                class={if @enabled, do: "", else: "hidden"}
              >
                <div class="form-control mb-4">
                  <label class="label"><span class="label-text font-medium">{t(
                    @locale,
                    @scope <> ".link_expiration",
                    %{}
                  )}</span></label>
                  <select
                    name="expiration"
                    class="select select-bordered w-full"
                    data-sharing-modal-target="expirationSelect"
                    data-action="change->sharing-modal#expirationChanged"
                  >
                    <option
                      :for={{label, value} <- @expirations}
                      value={value}
                      selected={if value == @expiration, do: "selected"}
                    >
                      {label}
                    </option>
                  </select>
                </div>
                <.sharing_link locale={@locale} url={@url} />
              </div>
            </form>
            <div class="alert alert-info mb-4">
              <Icon.icon name="info" class="size-6" />
              <div>
                <h3 class="font-bold">{t(@locale, @scope <> ".privacy_protection", %{})}</h3>
                <div class="text-sm">
                  {t(@locale, @scope <> ".exact_coordinates_are_hidden", %{})}<br />{t(
                    @locale,
                    @scope <> ".personal_information_is_not_included",
                    %{}
                  )}
                </div>
              </div>
            </div>
            <div class="modal-action">
              <button type="button" class="btn btn-primary" onclick="sharing_modal.close()">{t(
                @locale,
                @scope <> ".done",
                %{}
              )}</button>
            </div>
          </div>
        <% else %>
          <div class="text-center py-4">
            <p class="text-gray-600 mb-4">
              {t(
                @locale,
                "shared.sharing_modal.share_your_monthly_stats_publicly_with_friends_and_family_public",
                %{}
              )}
            </p>
            <a href={@upgrade} class="btn btn-primary">{t(
              @locale,
              "shared.sharing_modal.upgrade_to_pro",
              %{}
            )}</a>
          </div>
        <% end %>
      </div>
    </dialog>
    """
  end

  attr :locale, :string, required: true
  attr :url, :string, required: true

  def sharing_link(assigns) do
    ~H"""
    <div id="sharing-link-display" class="form-control mb-4">
      <label class="label"><span class="label-text font-medium">{t(
        @locale,
        "shared.sharing_link.sharing_link",
        %{}
      )}</span></label>
      <div class="join w-full">
        <input
          type="text"
          readonly
          class="input input-bordered join-item flex-1"
          data-sharing-modal-target="sharingLink"
          value={@url}
        />
        <button
          type="button"
          class="btn btn-outline join-item"
          data-action="click->sharing-modal#copyLink"
        ><Icon.icon name="copy" class="size-6" /> {t(@locale, "shared.sharing_link.copy", %{})}</button>
      </div>
      <div class="label">
        <span class="label-text-alt text-gray-500">{t(
          @locale,
          "shared.sharing_link.share_this_link_to_allow_others_to_view_your_stats",
          %{}
        )}</span>
      </div>
    </div>
    """
  end
end
