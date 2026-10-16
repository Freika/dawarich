defmodule DawarichWeb.InsightsLive.NativeRace do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{LocalizedDate, NativeChart, NumberFormat}
  alias Dawarich.Analytics.Period
  attr :race, :map, required: true
  attr :locale, :string, required: true
  attr :unit, :string, required: true
  attr :today, Date, required: true

  def render(assigns) do
    first = Date.new!(assigns.race.year, 1, 1)

    series = fn values ->
      for {meters, index} <- Enum.with_index(values),
          do: [
            Date.to_iso8601(Date.add(first, index)),
            Dawarich.Distance.convert(meters, assigns.unit)
          ]
    end

    chart = [%{name: to_string(assigns.race.year), data: series.(assigns.race.current)}]

    chart =
      if assigns.race.previous,
        do:
          chart ++
            [%{name: to_string(assigns.race.year - 1), data: series.(assigns.race.previous)}],
        else: chart

    assigns =
      assign(assigns,
        chart: chart,
        revision: :crypto.hash(:sha256, :erlang.term_to_binary(chart)) |> Base.encode16()
      )

    ~H"""
    <section data-testid="distance-race" class="my-4 min-w-0">
      <h2>
        {t(
          @locale,
          if(@race.previous,
            do: "insights.distance_race.title",
            else: "insights.distance_race.title_single"
          ),
          %{year: @race.year, previous: @race.year - 1}
        )}
      </h2>
      <p>
        {t(@locale, "insights.distance_race.so_far", %{year: @race.year})}: {distance(
          @locale,
          List.last(@race.current),
          @unit
        )}
      </p>
      <p>
        {t(@locale, "insights.distance_race.by_date", %{
          date: LocalizedDate.l(@locale, @race.last_date, "short_month_day")
        })}
      </p>
      <p :if={is_nil(@race.previous)}>
        {t(@locale, "insights.distance_race.no_previous", %{year: @race.year - 1})}
      </p>
      <%= if @race.previous do %>
        <p>
          {t(@locale, "insights.distance_race.same_day", %{year: @race.year - 1})}: {distance(
            @locale,
            Enum.at(@race.previous, length(@race.current) - 1),
            @unit
          )}
        </p>
        <p>
          {t(@locale, "insights.distance_race.ended_at", %{
            year: @race.year - 1,
            distance: distance(@locale, List.last(@race.previous), @unit)
          })}
        </p>
        <p data-testid="distance-race-lead">
          {t(@locale, lead_key(@race.lead), %{distance: distance(@locale, abs(@race.lead), @unit)})}
        </p>
      <% end %>
      <NativeChart.chart
        id="insights-distance-race"
        kind="LineChart"
        data={@chart}
        revision={@revision}
        label={
          t(@locale, "insights.distance_race.aria", %{year: @race.year, previous: @race.year - 1})
        }
        options={%{type: "line", suffix: " " <> @unit}}
      />
    </section>
    """
  end

  defp distance(locale, meters, unit),
    do: NumberFormat.delimited(locale, Period.rounded(meters, unit)) <> " " <> unit

  defp lead_key(0), do: "insights.distance_race.ahead"
  defp lead_key(n) when n > 0, do: "insights.distance_race.ahead"
  defp lead_key(_), do: "insights.distance_race.behind"
end
