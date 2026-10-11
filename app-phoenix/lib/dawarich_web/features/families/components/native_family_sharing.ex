defmodule DawarichWeb.NativeFamilySharing do
  @moduledoc false
  use DawarichWeb, :html
  attr :member, :map, required: true
  attr :locale, :string, required: true
  attr :now, :any, required: true

  def sharing(assigns) do
    ~H"""
    <section class="min-w-0 border rounded-xl p-3">
      <h2>{t(@locale, "families.show.your_sharing", %{})}</h2>
      <form
        id="native-family-sharing"
        phx-change="family:sharing"
        phx-submit="family:sharing"
        class="flex flex-wrap min-w-0 gap-3"
      >
        <label class="min-w-0 whitespace-normal">
          <input type="hidden" name="sharing[enabled]" value="false" />
          <input
            type="checkbox"
            name="sharing[enabled]"
            value="true"
            checked={@member.sharing.enabled?}
            class="toggle toggle-primary"
          />
          {s(@locale, "live_location")}
        </label>
        <select
          name="sharing[duration]"
          class="select select-bordered max-w-full"
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
        <p :if={@member.sharing.enabled? && @member.sharing.expires_at} class="text-xs min-w-0">
          {s(@locale, "expires_in_time", %{
            time:
              DawarichWeb.TimeAgo.words(
                @locale,
                Dawarich.Families.Clock.parse(@member.sharing.expires_at),
                @now
              )
          })}
        </p>
        <label class="min-w-0 whitespace-normal">
          <input type="hidden" name="sharing[share_history]" value="false" />
          <input
            type="checkbox"
            name="sharing[share_history]"
            value="true"
            checked={@member.sharing.share_history?}
            class="toggle toggle-secondary"
          />
          {s(@locale, "location_history")}
        </label>
        <select
          name="sharing[history_window]"
          class="select select-bordered max-w-full"
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
        <p class="min-w-0 text-xs">
          {s(@locale, "a_separate_setting_from_live_location_when_on_family_can")}
        </p>
      </form>
    </section>
    """
  end

  defp s(locale, key, bindings \\ %{}),
    do: t(locale, "families.location_sharing_toggle." <> key, bindings)
end
