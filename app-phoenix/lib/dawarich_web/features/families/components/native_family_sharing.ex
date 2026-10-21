defmodule DawarichWeb.NativeFamilySharing do
  @moduledoc false
  use DawarichWeb, :html
  attr :member, :map, required: true
  attr :locale, :string, required: true
  attr :now, :any, required: true

  def sharing(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl overflow-hidden">
      <div class="bg-base-200 px-4 py-2.5">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {t(@locale, "families.show.your_sharing", %{})}
        </h3>
      </div>
      <div class="p-4"><.toggle {assigns} event="family:sharing" /></div>
    </div>
    """
  end

  def toggle(assigns) do
    ~H"""
    <div>
      <form
        id="native-family-sharing"
        action="/family/location_sharing"
        accept-charset="UTF-8"
        method="post"
        phx-hook="FamilySharing"
        data-native-sharing-event={@event}
      >
        <input type="hidden" name="_method" value="patch" /><input
          type="hidden"
          name="authenticity_token"
          value={Plug.CSRFProtection.get_csrf_token()}
        />
        <input value={to_string(@member.sharing.enabled?)} type="hidden" name="enabled" id="enabled" />
        <input
          value={@member.sharing.duration || "permanent"}
          type="hidden"
          name="duration"
          id="duration"
        />
        <input
          value={to_string(@member.sharing.share_history?)}
          type="hidden"
          name="share_history"
          id="share_history"
        />
        <input
          value={@member.sharing.history_window}
          type="hidden"
          name="history_window"
          id="history_window"
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
            data-native-sharing-field="enabled"
            aria-label={s(@locale, "live_location")}
          />
          <div class="flex items-center gap-2">
            <div class={if !@member.sharing.enabled?, do: "hidden", else: ""}>
              <select
                class="select select-bordered select-md"
                data-native-sharing-field="duration"
                aria-label={s(@locale, "live_location")}
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
            <span class={"text-xs text-base-content/50" <> if(@member.sharing.enabled? && @member.sharing.expires_at, do: "", else: " hidden")}>
              <%= if @member.sharing.enabled? && @member.sharing.expires_at do %>
                {s(@locale, "expires_in_time", %{
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
          <template></template>
          <div class={if(@member.sharing.enabled?, do: "", else: "hidden") <> " contents"}>
            <span class="text-sm text-base-content/60 text-right whitespace-nowrap">{s(
              @locale,
              "location_history"
            )}</span>
            <input
              type="checkbox"
              class="toggle toggle-secondary toggle-md"
              checked={@member.sharing.share_history?}
              data-native-sharing-field="share_history"
              aria-label={s(@locale, "location_history")}
            />
            <div class={if !@member.sharing.share_history?, do: "hidden", else: ""}>
              <select
                class="select select-bordered select-md"
                data-native-sharing-field="history_window"
                aria-label={s(@locale, "location_history")}
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
    """
  end

  defp s(locale, key, bindings \\ %{}),
    do: t(locale, "families.location_sharing_toggle." <> key, bindings)
end
