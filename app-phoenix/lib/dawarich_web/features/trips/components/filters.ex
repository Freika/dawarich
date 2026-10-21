defmodule DawarichWeb.TripsNative.Filters do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Trips.IndexQuery

  attr :locale, :string, required: true
  attr :form, :any, required: true
  attr :options, :map, required: true
  attr :query, :map, required: true

  def filters(assigns) do
    {:ok, months} = Dawarich.I18n.t(assigns.locale, "date.month_names")

    assigns =
      assign(assigns,
        months: months,
        years: selected(assigns.options.years, assigns.query.year) |> Enum.sort(:desc),
        countries:
          selected(assigns.options.countries, assigns.query.country)
          |> Enum.sort_by(&String.downcase/1),
        sorts: ~w(newest oldest name distance),
        active: IndexQuery.active?(assigns.query) or assigns.query.sort != "newest",
        label_class:
          "text-xs font-medium text-base-content/50 uppercase tracking-wider mb-1 block"
      )

    ~H"""
    <div class="border border-base-300 rounded-xl bg-base-200/50 p-4 mb-5">
      <form
        id="native-trip-filters"
        phx-submit="trips:filter"
        class="flex flex-wrap items-end gap-3"
        role="search"
        action="/trips"
        accept-charset="UTF-8"
        method="get"
      >
        <div class="min-w-0 flex-[2_1_16rem]">
          <label class={@label_class} for="q">{f(@locale, "search")}</label>
          <input
            name="q"
            id="q"
            value={@query.q}
            type="search"
            maxlength="100"
            size="100"
            placeholder={f(@locale, "search_placeholder")}
            class="input input-bordered input-sm w-full"
          />
        </div>
        <div class="min-w-0 flex-[1_1_9rem]">
          <label class={@label_class} for="sort">{f(@locale, "sort")}</label>
          <select name="sort" id="sort" class="select select-bordered select-sm w-full">
            <option :for={sort <- @sorts} value={sort} selected={sort == @query.sort}>
              {f(@locale, "sorts." <> sort)}
            </option>
          </select>
        </div>
        <div class="min-w-0 flex-[1_1_7rem]">
          <label class={@label_class} for="year">{f(@locale, "year")}</label>
          <select name="year" id="year" class="select select-bordered select-sm w-full">
            <option value="">{f(@locale, "all_years")}</option>
            <option :for={year <- @years} value={year} selected={year == @query.year}>{year}</option>
          </select>
        </div>
        <div class="min-w-0 flex-[1_1_8rem]">
          <label class={@label_class} for="month">{f(@locale, "month")}</label>
          <select
            name="month"
            id="month"
            class="select select-bordered select-sm w-full"
            disabled={is_nil(@query.year)}
            aria-describedby={is_nil(@query.year) && "trips-month-hint"}
          >
            <option value="">{f(@locale, "all_months")}</option>
            <option :for={month <- 1..12} value={month} selected={month == @query.month}>
              {Enum.at(@months, month)}
            </option>
          </select>
          <span :if={is_nil(@query.year)} id="trips-month-hint" class="sr-only">{f(
            @locale,
            "choose_year_first"
          )}</span>
        </div>
        <div :if={@countries != []} class="min-w-0 flex-[1_1_9rem]">
          <label class={@label_class} for="country">{f(@locale, "country")}</label>
          <select name="country" id="country" class="select select-bordered select-sm w-full">
            <option value="">{f(@locale, "all_countries")}</option>
            <option :for={country <- @countries} value={country} selected={country == @query.country}>
              {country}
            </option>
          </select>
        </div>
        <div class="flex gap-2">
          <input type="submit" value={f(@locale, "apply")} class="btn btn-primary btn-sm" />
          <.link :if={@active} patch="/trips" class="btn btn-sm">{f(@locale, "reset")}</.link>
        </div>
      </form>
    </div>
    """
  end

  defp selected(options, value) when value in [nil, ""], do: options
  defp selected(options, value), do: if(value in options, do: options, else: [value | options])
  defp f(locale, key), do: t(locale, "trips.filters." <> key, %{})
end
