defmodule DawarichWeb.FamilyNativeControls do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS

  def errors(assigns) do
    ~H"""
    <div
      :if={@errors != []}
      id="family-errors"
      class="alert alert-error min-w-0 [overflow-wrap:anywhere]"
      role="alert"
    >
      <ul>
        <li :for={error <- @errors}>{error}</li>
      </ul>
    </div>
    """
  end

  def confirm_button(assigns) do
    assigns = assign_new(assigns, :id, fn -> nil end)

    assigns =
      assign_new(assigns, :class, fn -> "btn btn-outline btn-error h-auto whitespace-normal" end)

    ~H"""
    <button
      type="button"
      data-family-action={@action}
      data-family-target={@id}
      class={@class}
      phx-click={
        JS.push("family_prepare_confirm", value: %{action: @action, id: @id})
        |> JS.dispatch("dawarich:open-dialog", to: "#family-confirm")
      }
    >
      {@label}
    </button>
    """
  end

  def confirmation(assigns) do
    ~H"""
    <dialog
      id="family-confirm"
      aria-labelledby="family-confirm-title"
      phx-hook="FamilyConfirm"
      data-pending={to_string(@confirmation != nil)}
      class="modal"
    >
      <div class="modal-box min-w-0 [overflow-wrap:anywhere]">
        <h2 id="family-confirm-title" class="text-xl font-semibold">
          {t(@locale, "javascript.common.confirm", %{})}
        </h2>
        <p class="py-4">{confirm_text(@confirmation, @page, @locale)}</p>
        <div class="modal-action flex-wrap">
          <button
            type="button"
            class="btn h-auto whitespace-normal"
            phx-click={
              JS.push("family_cancel_confirm")
              |> JS.dispatch("dawarich:close-dialog", to: "#family-confirm")
            }
          >{t(@locale, "javascript.common.cancel", %{})}</button>
          <button
            type="button"
            class="btn btn-error h-auto whitespace-normal"
            phx-click="family_confirm"
            phx-disable-with={t(@locale, "javascript.common.confirm", %{})}
          >{t(@locale, "javascript.common.confirm", %{})}</button>
        </div>
      </div>
    </dialog>
    """
  end

  def danger(assigns) do
    ~H"""
    <div :if={@page[:family]} class="flex flex-wrap justify-end gap-2 mt-5">
      <.confirm_button
        :if={!@page.owner?}
        action="remove_member"
        id={@page.me.membership_id}
        label={t(@locale, "families.show.leave_family", %{})}
      />
      <.confirm_button
        :if={@page.owner?}
        action="delete"
        label={t(@locale, "families.show.delete_family", %{})}
      />
    </div>
    """
  end

  def sharing(assigns) do
    before =
      get_in(assigns.current_scope.user.settings, [
        "family",
        "location_sharing",
        "history_before_sharing"
      ])

    assigns = assign(assigns, :history_before, before == true)

    ~H"""
    <form
      id="native-family-sharing"
      phx-change="family_set_sharing"
      phx-submit="family_set_sharing"
      class="space-y-4 min-w-0"
    >
      <div class="flex flex-wrap gap-3 items-center">
        <input type="hidden" name="enabled" value="0" />
        <input
          id="native-sharing-enabled"
          type="checkbox"
          name="enabled"
          value="1"
          checked={@member.sharing.enabled?}
          class="toggle toggle-primary"
        />
        <label for="native-sharing-enabled" class="text-sm min-w-0">{s(@locale, "live_location")}</label>
      </div>
      <div>
        <label for="native-sharing-duration" class="label label-text">{t(
          @locale,
          "family.location_requests.show.share_location_for",
          %{}
        )}</label>
        <select id="native-sharing-duration" name="duration" class="select select-bordered w-full">
          <option
            :for={{value, key} <- durations()}
            value={value}
            selected={@member.sharing.duration == value}
          >
            {s(@locale, key)}
          </option>
        </select>
        <p :if={@member.sharing.enabled? and @member.sharing.expires_at} class="text-xs mt-2">
          {s(@locale, "expires_in_time", %{
            time:
              DawarichWeb.TimeAgo.words(
                @locale,
                Dawarich.Families.Clock.parse(@member.sharing.expires_at),
                @now
              )
          })}
        </p>
      </div>
      <div class="flex flex-wrap gap-3 items-center">
        <input type="hidden" name="share_history" value="0" />
        <input
          id="native-sharing-history"
          type="checkbox"
          name="share_history"
          value="1"
          checked={@member.sharing.share_history?}
          class="toggle toggle-secondary"
        />
        <label for="native-sharing-history" class="text-sm">{s(@locale, "location_history")}</label>
      </div>
      <p class="text-xs text-base-content/60">
        {s(@locale, "a_separate_setting_from_live_location_when_on_family_can")}
      </p>
      <div>
        <label for="native-sharing-window" class="label label-text">{s(@locale, "location_history")}</label>
        <select id="native-sharing-window" name="history_window" class="select select-bordered w-full">
          <option
            :for={{value, key} <- windows()}
            value={value}
            selected={@member.sharing.history_window == value}
          >
            {s(@locale, key)}
          </option>
        </select>
      </div>
      <input
        type="hidden"
        name="history_before_sharing"
        value={if @history_before, do: "1", else: "0"}
      />
    </form>
    """
  end

  defp confirm_text(nil, _, _), do: ""

  defp confirm_text(%{action: "delete"}, _, locale),
    do: t(locale, "families.show.delete_this_family_this_cannot_be_undone", %{})

  defp confirm_text(%{action: "cancel_invitation"}, _, locale),
    do: t(locale, "families.show.cancel_this_invitation", %{})

  defp confirm_text(%{action: "remove_member", id: id}, %{me: %{membership_id: id}}, locale),
    do: t(locale, "families.show.are_you_sure_you_want_to_leave_this_family", %{})

  defp confirm_text(%{action: "remove_member", id: id}, page, locale) do
    member = Enum.find(page[:members] || [], &(&1.membership_id == id))

    t(locale, "families.show.remove_email_from_the_family", %{
      email: if(member, do: member.email, else: "")
    })
  end

  defp s(locale, key, bindings \\ %{}),
    do: t(locale, "families.location_sharing_toggle." <> key, bindings)

  defp durations,
    do: [
      {"permanent", "always"},
      {"1h", "hour"},
      {"6h", "hours"},
      {"12h", "hours_2"},
      {"24h", "hours_3"}
    ]

  defp windows,
    do: [
      {"24h", "last_24_hours"},
      {"7d", "last_7_days"},
      {"30d", "last_30_days"},
      {"all", "since_sharing_started"}
    ]
end
