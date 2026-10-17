defmodule DawarichWeb.TripsNative.Filters do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  attr :locale, :string, required: true
  attr :form, :any, required: true
  attr :options, :map, required: true
  attr :query, :map, required: true

  def filters(assigns) do
    {:ok, months} = Dawarich.I18n.t(assigns.locale, "date.month_names")

    assigns =
      assign(assigns,
        months: months,
        years: selected(assigns.options.years, assigns.query.year),
        countries: selected(assigns.options.countries, assigns.query.country),
        sorts: ~w(newest oldest name distance)
      )

    ~H"""
    <.form
      for={@form}
      id="trip-filters"
      phx-submit="trips:filter"
      class="flex flex-wrap items-end gap-3 mb-5 min-w-0"
    >
      <label class="min-w-0 flex-1">
        {f(@locale, "search")}
        <input
          name={@form[:q].name}
          value={@query.q}
          type="search"
          maxlength="100"
          placeholder={f(@locale, "search_placeholder")}
          class="input input-bordered w-full min-w-0"
        />
      </label>
      <label>
        {f(@locale, "year")}
        <select name={@form[:year].name} class="select select-bordered w-full">
          <option value="">{f(@locale, "all_years")}</option>
          <option :for={year <- @years} value={year} selected={year == @query.year}>{year}</option>
        </select>
      </label>
      <label>
        {f(@locale, "month")}
        <select
          name={@form[:month].name}
          disabled={is_nil(@query.year)}
          class="select select-bordered w-full"
          title={is_nil(@query.year) && f(@locale, "choose_year_first")}
        >
          <option value="">{f(@locale, "all_months")}</option>
          <option :for={month <- 1..12} value={month} selected={month == @query.month}>
            {Enum.at(@months, month)}
          </option>
        </select>
      </label>
      <label>
        {f(@locale, "country")}
        <select name={@form[:country].name} class="select select-bordered w-full">
          <option value="">{f(@locale, "all_countries")}</option>
          <option :for={country <- @countries} value={country} selected={country == @query.country}>
            {country}
          </option>
        </select>
      </label>
      <label>
        {f(@locale, "sort")}
        <select name={@form[:sort].name} class="select select-bordered w-full">
          <option :for={sort <- @sorts} value={sort} selected={sort == @query.sort}>
            {f(@locale, "sorts." <> sort)}
          </option>
        </select>
      </label>
      <button type="submit" class="btn btn-primary">{f(@locale, "apply")}</button>
      <.link patch="/trips" class="btn btn-ghost">{f(@locale, "reset")}</.link>
    </.form>
    """
  end

  defp selected(options, value) when value in [nil, ""], do: options
  defp selected(options, value), do: if(value in options, do: options, else: [value | options])
  defp f(locale, key), do: t(locale, "trips.filters." <> key, %{})
end
