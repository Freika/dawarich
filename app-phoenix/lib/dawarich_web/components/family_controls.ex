defmodule DawarichWeb.FamilyControls do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  def sharing_toggle(assigns) do
    ~H"""
    <turbo-frame id={"location-sharing-#{@member.id}"}>
      <div
        data-controller="location-sharing-toggle"
        data-location-sharing-toggle-member-id-value={@member.id}
        data-location-sharing-toggle-enabled-value={to_string(@member.sharing.enabled?)}
        data-location-sharing-toggle-expires-at-value={@member.sharing.expires_at || ""}
      >
        <form
          action="/family/location_sharing"
          accept-charset="UTF-8"
          method="post"
          data-turbo-frame={"location-sharing-#{@member.id}"}
          data-location-sharing-toggle-target="form"
        >
          <input type="hidden" name="_method" value="patch" />
          <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
          <input
            type="hidden"
            name="enabled"
            id="enabled"
            value={to_string(@member.sharing.enabled?)}
            data-location-sharing-toggle-target="enabledField"
          />
          <input
            type="hidden"
            name="duration"
            id="duration"
            value={@member.sharing.duration}
            data-location-sharing-toggle-target="durationField"
          />
          <input
            type="hidden"
            name="share_history"
            id="share_history"
            value={to_string(@member.sharing.share_history?)}
            data-location-sharing-toggle-target="shareHistoryField"
          />
          <input
            type="hidden"
            name="history_window"
            id="history_window"
            value={@member.sharing.history_window}
            data-location-sharing-toggle-target="historyWindowField"
          />
          <div class="grid grid-cols-[auto_auto_1fr] items-center gap-x-3 gap-y-2">
            <span class="text-sm text-base-content/60 text-right whitespace-nowrap">{s(
              @locale,
              "live_location"
            )}</span>
            <input
              type="checkbox"
              class="toggle toggle-primary toggle-md"
              checked={@member.sharing.enabled?}
              data-location-sharing-toggle-target="checkbox"
              data-action="change->location-sharing-toggle#toggle"
            />
            <div class="flex items-center gap-2">
              <div
                class={if(!@member.sharing.enabled?, do: "hidden")}
                data-location-sharing-toggle-target="durationContainer"
              >
                <select
                  class="select select-bordered select-md"
                  data-location-sharing-toggle-target="durationSelect"
                  data-action="change->location-sharing-toggle#changeDuration"
                >
                  <option
                    :for={
                      {value, key} <- [
                        {"permanent", "always"},
                        {"1h", "hour"},
                        {"6h", "hours"},
                        {"12h", "hours_2"},
                        {"24h", "hours_3"}
                      ]
                    }
                    value={value}
                    selected={@member.sharing.duration == value}
                  >
                    {s(@locale, key)}
                  </option>
                </select>
              </div>
              <span
                class={
                  if(!@member.sharing.enabled? or is_nil(@member.sharing.expires_at),
                    do: "text-xs text-base-content/50 hidden",
                    else: "text-xs text-base-content/50"
                  )
                }
                data-location-sharing-toggle-target="expirationInfo"
              >
                <%= if @member.sharing.enabled? and @member.sharing.expires_at do %>
                  {t(@locale, "families.location_sharing_toggle.expires_in_time", %{
                    time:
                      DawarichWeb.TimeAgo.words(
                        @locale,
                        Dawarich.Families.Clock.parse(@member.sharing.expires_at),
                        @now
                      )
                  })}
                <% end %>
              </span>
            </div>
            <template data-location-sharing-toggle-target="historyRow"></template>
            <div
              class={if(@member.sharing.enabled?, do: "contents", else: "hidden contents")}
              data-location-sharing-toggle-target="historyContainer"
            >
              <span class="text-sm text-base-content/60 text-right whitespace-nowrap">{s(
                @locale,
                "location_history"
              )}</span>
              <input
                type="checkbox"
                class="toggle toggle-secondary toggle-md"
                checked={@member.sharing.share_history?}
                data-location-sharing-toggle-target="historyCheckbox"
                data-action="change->location-sharing-toggle#toggleHistory"
              />
              <div
                class={if(!@member.sharing.share_history?, do: "hidden")}
                data-location-sharing-toggle-target="historyWindowContainer"
              >
                <select
                  class="select select-bordered select-md"
                  data-location-sharing-toggle-target="historyWindowSelect"
                  data-action="change->location-sharing-toggle#changeHistoryWindow"
                >
                  <option
                    :for={
                      {value, key} <- [
                        {"24h", "last_24_hours"},
                        {"7d", "last_7_days"},
                        {"30d", "last_30_days"},
                        {"all", "since_sharing_started"}
                      ]
                    }
                    value={value}
                    selected={@member.sharing.history_window == value}
                  >
                    {s(@locale, key)}
                  </option>
                </select>
              </div>
              <p class="col-span-full text-xs text-base-content/50 leading-snug">
                {s(@locale, "a_separate_setting_from_live_location_when_on_family_can")}
              </p>
            </div>
          </div>
        </form>
      </div>
    </turbo-frame>
    """
  end

  def family_danger(assigns) do
    ~H"""
    <div class="flex gap-2 justify-end">
      <a
        :if={!@page.owner?}
        href={"/family/members/#{@page.me.membership_id}"}
        data-turbo-confirm={t(@locale, @scope <> ".are_you_sure_you_want_to_leave_this_family", %{})}
        data-turbo-method="delete"
        class="btn btn-ghost btn-xs text-warning"
      >{t(@locale, @scope <> ".leave_family", %{})}</a>
      <a
        :if={@page.owner?}
        href="/family"
        data-turbo-confirm={t(@locale, @scope <> ".delete_this_family_this_cannot_be_undone", %{})}
        data-turbo-method="delete"
        class="btn btn-ghost btn-xs text-error"
      ><.icon name="trash-2" class="w-3.5 h-3.5" /> {t(@locale, @scope <> ".delete_family", %{})}</a>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "families.location_sharing_toggle." <> key, %{})
end
