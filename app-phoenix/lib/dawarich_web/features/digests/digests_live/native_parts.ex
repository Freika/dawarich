defmodule DawarichWeb.DigestsLive.NativeParts do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.Digests
  alias DawarichWeb.{DigestFormat, Icon}

  attr :locale, :string, required: true
  attr :digest, :map, required: true
  attr :unit, :string, required: true

  def summary(assigns) do
    ~H"""
    <div
      class="hero text-white rounded-lg shadow-lg mb-8"
      style="background: linear-gradient(135deg, #0f766e, #0284c7);"
    >
      <div class="hero-content text-center py-12 relative w-full">
        <div class="max-w-lg">
          <h1 class="text-4xl font-bold">
            {t(@locale, "users.digests.show.year_year_in_review", %{year: @digest.year})}
          </h1>
          <p class="py-4">{t(@locale, "users.digests.show.your_journey_by_the_numbers", %{})}</p>
          <button
            class="btn btn-outline btn-sm text-neutral border-neutral hover:bg-white hover:text-primary"
            phx-click="open_share"
          >
            <Icon.icon name="share" class="size-6" /> {t(@locale, "users.digests.show.share", %{})}
          </button>
        </div>
      </div>
    </div>
    <div class="card bg-base-200 shadow-xl mb-8">
      <div class="card-body text-center items-center">
        <div class="stat-title flex items-center gap-2">
          <Icon.icon name="map" class="size-6" /> {t(
            @locale,
            "users.digests.show.distance_traveled",
            %{}
          )}
        </div>
        <div class="stat-value text-primary text-4xl my-4">
          {DigestFormat.distance_with_unit(@locale, @digest.distance, @unit)}
        </div>
        <p class="text-gray-600">{DigestFormat.comparison_text(@locale, @digest.distance)}</p>
        <p
          :if={@digest[:yoy_distance_change] != nil}
          class={"mt-2 font-semibold #{DigestFormat.yoy_class(@digest[:yoy_distance_change])}"}
        >
          {DigestFormat.yoy_text(@digest[:yoy_distance_change])} {t(
            @locale,
            "users.digests.show.compared_to",
            %{}
          )} {@digest[:previous_year]}
        </p>
      </div>
    </div>
    <div class="stats shadow w-full mb-8 bg-base-200">
      <.first_time_stat
        locale={@locale}
        icon="globe"
        label="countries"
        count={@digest[:countries_count] || Digests.countries_count(@digest.toponyms)}
        firsts={@digest.first_time_countries}
        firsts_count={@digest[:first_time_countries_count] || length(@digest.first_time_countries)}
        value_class="text-secondary"
      />
      <.first_time_stat
        locale={@locale}
        icon="building"
        label="cities"
        count={@digest[:cities_count] || Digests.cities_count(@digest.toponyms)}
        firsts={@digest.first_time_cities}
        firsts_count={@digest[:first_time_cities_count] || length(@digest.first_time_cities)}
        value_class="text-accent"
      />
    </div>
    """
  end

  defp first_time_stat(assigns) do
    ~H"""
    <div class="stat place-items-center">
      <div class="stat-title flex items-center gap-1">
        <Icon.icon name={@icon} class="size-6" /> {t(@locale, "users.digests.show." <> @label, %{})}
      </div>
      <div class={"stat-value #{@value_class}"}>{@count}</div>
      <div class={"stat-desc font-medium flex items-center gap-1 #{if @firsts_count>0, do: "text-success", else: "invisible"}"}>
        <Icon.icon name="star" class="size-6" /> {t(@locale, "users.digests.show.first_time_count", %{
          count: @firsts_count
        })}
      </div>
    </div>
    """
  end
end
