defmodule DawarichWeb.NativeResidency do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  attr :residency, :map, default: nil
  attr :locale, :string, required: true

  def card(%{residency: nil} = assigns), do: ~H""

  def card(assigns) do
    ~H"""
    <section id="native-residency" class="min-w-0" data-residency-year={@residency.year}>
      <%= if @residency.countries == [] do %>
        <p class="text-sm">{s(@locale, "no_country_data_for")} {@residency.year}.</p>
        <p class="text-xs">{s(@locale, "points_need_reverse_geocoding_to_detect_countries")}</p>
      <% else %>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="text-lg font-semibold min-w-0">{s(@locale, "days_per_country")}</h3>
          <div class="badge badge-ghost">
            {@residency.total} / {@residency.days_in_year} {s(@locale, "days")}
          </div>
        </div>
        <ol class="mt-2 space-y-1" data-testid="residency-country-list">
          <li
            :for={country <- @residency.countries}
            class="flex flex-wrap items-center gap-2 text-sm"
            data-residency-country={country.name}
          >
            <span class={"w-3 h-3 rounded-sm #{@residency.colors[country.name]}"} aria-hidden="true"></span>
            <span class="min-w-0 [overflow-wrap:anywhere]">{country.name}</span>
            <span class="ml-auto tabular-nums">{country.days} {s(@locale, "days")}</span>
          </li>
        </ol>
      <% end %>
    </section>
    """
  end

  defp s(locale, key), do: t(locale, "map.residency.show." <> key, %{})
end
