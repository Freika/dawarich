defmodule DawarichWeb.StatsLive.Month do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.StatsCards, only: [plan_alert: 1]

  alias Dawarich.{LocalTime, Stats}
  alias DawarichWeb.{Assets, LocalizedDate, Params, RailsWidgets, StatsFormat, StatsMonth}

  @off [nil, "", false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, RailsWidgets.rails_flash(socket, params)}

  def page(user, %{"year" => year, "month" => month}, %{
        locale: locale,
        now: now,
        self_hosted: self_hosted,
        base_url: base_url
      }) do
    {year, month} = {Params.ruby_to_i(year), Params.ruby_to_i(month)}
    context = Stats.context(user, now, self_hosted)
    data = Stats.month(user, year, month, context, previous_month: month - 1)
    if data.stat, do: validate_daily!(data.stat.daily)
    peak = data.stat && StatsFormat.peak(data.stat.daily)
    settings = Dawarich.UserSettings.get(user)

    %{
      page_title:
        t(locale, "stats.month.month_year_monthly_digest", %{
          month: LocalizedDate.month_name(locale, year, month),
          year: year
        }),
      rails_js: true,
      year: year,
      month: month,
      restricted: context.restricted,
      data: data,
      peak: peak,
      bounds: peak && LocalTime.day_bounds(context.zone, Date.new!(year, month, elem(peak, 0))),
      unit: StatsFormat.unit(settings),
      tiles_url:
        if(is_binary(settings["maps_maplibre_tiles_url"]),
          do: settings["maps_maplibre_tiles_url"],
          else: ""
        ),
      tiles_fallback: to_string(settings["maps_maplibre_tiles_fallback"] not in @off),
      bg_url: base_url <> Assets.stylesheet_path(StatsFormat.month_background(month)),
      sharing_allowed: not context.restricted,
      sharing_url: sharing_url(data.stat, base_url),
      sharing_upgrade: StatsFormat.upgrade_url(user, now, self_hosted, "stats", "sharing"),
      alert_href: StatsFormat.upgrade_url(user, now, self_hosted, "data_window", "stats_month")
    }
  end

  defp validate_daily!(daily) when is_list(daily), do: :ok
  defp validate_daily!(_daily), do: raise(ArgumentError, "invalid daily_distance")

  defp sharing_url(%{sharing: %{enabled: true}, sharing_uuid: uuid}, base_url)
       when is_binary(uuid),
       do: base_url <> "/shared/month/" <> uuid

  defp sharing_url(_stat, _base_url), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <.plan_alert :if={@restricted} locale={@locale} href={@alert_href} />
      <%= if @data.stat do %>
        <StatsMonth.month_digest
          locale={@locale}
          year={@year}
          month={@month}
          stat={@data.stat}
          previous={@data.previous}
          average_km={@data.average_km}
          unit={@unit}
          peak={@peak}
          bounds={@bounds}
          api_key={@current_user.api_key || ""}
          tiles_url={@tiles_url}
          tiles_fallback={@tiles_fallback}
          bg_url={@bg_url}
          sharing_allowed={@sharing_allowed}
          sharing_url={@sharing_url}
          sharing_upgrade={@sharing_upgrade}
          csrf={@rails_csrf_token}
        />
      <% else %>
        <div class="alert" phx-no-format>{t(@locale, "stats.month.no_location_data_available_for_this_month", %{})}</div>
      <% end %>
    </div>
    """
  end
end
