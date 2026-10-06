defmodule DawarichWeb.PublicDigest do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Digests
  alias DawarichWeb.{Chartkick, DigestFormat, Icon, YearCards}

  def document(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto px-4 py-8">
      <div
        class="hero text-white rounded-lg shadow-lg mb-8"
        style="background: linear-gradient(135deg, #0f766e, #0284c7);"
      >
        <div class="hero-content text-center py-12">
          <div class="max-w-lg">
            <h1 class="text-4xl font-bold">
              {t(@locale, "users.digests.public_year.year_year_in_review", %{year: @digest.year})}
            </h1>
            <p class="py-4">
              {t(@locale, "users.digests.public_year.your_journey_by_the_numbers", %{})}
            </p>
          </div>
        </div>
      </div>
      <div class="stats shadow mx-auto mb-8 w-full">
        <div class="stat place-items-center text-center">
          <div class="stat-title">
            {t(@locale, "users.digests.public_year.distance_traveled", %{})}
          </div>
          <div class="stat-value">
            {DigestFormat.distance_with_unit(@locale, @digest.distance, @unit)}
          </div>
          <div class="stat-desc">{DigestFormat.comparison_text(@locale, @digest.distance)}</div>
        </div>
        <div class="stat place-items-center text-center">
          <div class="stat-title">
            {t(@locale, "users.digests.public_year.countries_visited", %{})}
          </div>
          <div class="stat-value text-secondary">{Digests.countries_count(@digest.toponyms)}</div>
          <div class={"stat-desc #{if @digest.first_time_countries != [], do: "text-success", else: "invisible"}"}>
            {t(@locale, "users.digests.public_year.first_time_count", %{
              count: length(@digest.first_time_countries)
            })}
          </div>
        </div>
        <div class="stat place-items-center text-center">
          <div class="stat-title">{t(@locale, "users.digests.public_year.cities_explored", %{})}</div>
          <div class="stat-value text-accent">{Digests.cities_count(@digest.toponyms)}</div>
          <div class={"stat-desc #{if @digest.first_time_cities != [], do: "text-success", else: "invisible"}"}>
            {t(@locale, "users.digests.public_year.first_time_count", %{
              count: length(@digest.first_time_cities)
            })}
          </div>
        </div>
      </div>
      <%= if @full do %>
        <%= if @digest.first_time_countries != [] or @digest.first_time_cities != [] do %>
          <div class="card bg-base-100 shadow-xl mb-8">
            <div class="card-body text-center items-center">
              <h2 class="card-title">
                <Icon.icon name="star" class="size-6" /> {t(
                  @locale,
                  "users.digests.public_year.first_time_visits",
                  %{}
                )}
              </h2>
              <%= if @digest.first_time_countries != [] do %>
                <div class="mb-4">
                  <h3 class="font-semibold mb-2">
                    {t(@locale, "users.digests.public_year.new_countries", %{})}
                  </h3>
                  <div class="flex flex-wrap gap-2 justify-center">
                    <%= for country <- @digest.first_time_countries do %>
                      <span class="badge badge-success badge-lg">{country}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <%= if @digest.first_time_cities != [] do %>
                <div>
                  <h3 class="font-semibold mb-2">
                    {t(@locale, "users.digests.public_year.new_cities", %{})}
                  </h3>
                  <div class="flex flex-wrap gap-2 justify-center">
                    <%= for city <- Enum.take(@digest.first_time_cities, 5) do %>
                      <span class="badge badge-outline">{city}</span>
                    <% end %>
                    <%= if length(@digest.first_time_cities) > 5 do %>
                      <span class="badge badge-ghost">+{length(@digest.first_time_cities) - 5} {t(
                        @locale,
                        "users.digests.public_year.more",
                        %{}
                      )}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        <%= if @digest.monthly_distances != [] do %>
          <div class="card bg-base-100 shadow-xl mb-8">
            <div class="card-body text-center items-center">
              <h2 class="card-title">
                <Icon.icon name="activity" class="size-6" /> {t(
                  @locale,
                  "users.digests.public_year.year_by_month",
                  %{}
                )}
              </h2>
              <div class="w-full h-48 bg-base-200 rounded-lg p-4 relative">
                <Chartkick.column_chart
                  id="chart-1"
                  height="200px"
                  data={DigestFormat.monthly_chart(@locale, @digest.monthly_distances, @unit)}
                  options={[
                    suffix: " " <> @unit,
                    xtitle: t(@locale, "users.digests.public_year.month", %{}),
                    ytitle: t(@locale, "users.digests.public_year.distance", %{}),
                    colors: YearCards.month_colors()
                  ]}
                />
              </div>
            </div>
          </div>
        <% end %>
        <%= if @digest.top_countries != [] do %>
          <div class="card bg-base-100 shadow-xl mb-8">
            <div class="card-body text-center items-center">
              <h2 class="card-title">
                <Icon.icon name="map-pin" class="size-6" /> {t(
                  @locale,
                  "users.digests.public_year.where_they_spent_the_most_time",
                  %{}
                )}
              </h2>
              <ul class="space-y-2 w-full">
                <%= for country <- Enum.take(@digest.top_countries, 3) do %>
                  <li class="flex justify-between items-center p-3 bg-base-200 rounded-lg">
                    <span class="font-semibold">
                      <span class="mr-1"><Icon.country_flag name={country["name"]} table={@table} /></span>
                      {country["name"]}
                    </span>
                    <span class="text-gray-600">{DigestFormat.time_spent(@locale, country["minutes"])}</span>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        <% end %>
        <div class="card bg-base-100 shadow-xl mb-8">
          <div class="card-body text-center items-center">
            <h2 class="card-title">
              <Icon.icon name="earth" class="size-6" /> {t(
                @locale,
                "users.digests.public_year.countries_cities",
                %{}
              )}
            </h2>
            <div class="space-y-4 w-full">
              <%= for {country, index} <- Enum.with_index(@digest.toponyms) do %>
                <div class="space-y-2">
                  <div class="flex justify-between items-center">
                    <span class="font-semibold">
                      <span class="mr-1"><Icon.country_flag name={country["country"]} table={@table} /></span>
                      {country["country"]}
                    </span>
                    <span class="text-sm">{length(country["cities"] || [])} {t(
                      @locale,
                      "users.digests.public_year.cities",
                      %{}
                    )}</span>
                  </div>
                  <progress
                    class="progress progress-primary w-full"
                    value={100 - index * 15}
                    max="100"
                  ></progress>
                </div>
              <% end %>
            </div>
            <div class="divider"></div>
            <div class="flex flex-wrap gap-2 justify-center w-full">
              <span class="text-sm font-medium">{t(
                @locale,
                "users.digests.public_year.cities_visited",
                %{}
              )}</span>
              <%= for country <- @digest.toponyms do %>
                <%= for city <- Enum.take(country["cities"] || [], 5) do %>
                  <div class="badge badge-outline">{city["city"]}</div>
                <% end %>
                <%= if length(country["cities"] || []) > 5 do %>
                  <div class="badge badge-ghost">
                    +{length(country["cities"]) - 5} {t(
                      @locale,
                      "users.digests.public_year.more",
                      %{}
                    )}
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
        <div class="card bg-slate-800 text-white shadow-xl mb-8">
          <div class="card-body text-center items-center">
            <h2 class="card-title text-white">
              <Icon.icon name="trophy" class="size-6" /> {t(
                @locale,
                "users.digests.public_year.all_time_stats",
                %{}
              )}
            </h2>
            <div class="grid grid-cols-2 gap-4 mt-4">
              <div class="stat place-items-center">
                <div class="stat-title text-gray-400">
                  {t(@locale, "users.digests.public_year.countries_visited", %{})}
                </div>
                <div class="stat-value text-white">{@digest.total_countries_all_time}</div>
              </div>
              <div class="stat place-items-center">
                <div class="stat-title text-gray-400">
                  {t(@locale, "users.digests.public_year.cities_explored", %{})}
                </div>
                <div class="stat-value text-white">{@digest.total_cities_all_time}</div>
              </div>
            </div>
            <div class="stat place-items-center mt-2">
              <div class="stat-title text-gray-400">
                {t(@locale, "users.digests.public_year.total_distance", %{})}
              </div>
              <div class="stat-value text-white">
                {DigestFormat.distance_with_unit(@locale, @digest.total_distance_all_time, @unit)}
              </div>
            </div>
          </div>
        </div>
      <% end %>
      <div class="text-center py-8">
        <div class="text-sm text-gray-500">
          {t(@locale, "users.digests.public_year.track_your_own_adventures_with", %{})}
          <a
            href="https://dawarich.app?utm_source=shared_digest&utm_medium=referral&utm_campaign=year_in_review"
            class="link link-primary"
            target="_blank"
          >{t(@locale, "users.digests.public_year.dawarich", %{})}</a> {t(
            @locale,
            "users.digests.public_year.your_personal_memories_mapper",
            %{}
          )}
        </div>
      </div>
    </div>
    """
  end
end
