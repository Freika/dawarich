defmodule DawarichWeb.DigestFullParts do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{Chartkick, DigestFormat, Icon, StatsFormat, YearCards}

  @ranks ~w(badge-primary badge-secondary badge-accent badge-info badge-success)

  attr :locale, :string, required: true
  attr :digest, :map, required: true
  attr :unit, :string, required: true
  attr :table, :list, required: true

  def full(assigns) do
    assigns =
      assign(assigns,
        untracked: DigestFormat.untracked_days(assigns.digest.year, assigns.digest.total_minutes),
        ranks: @ranks
      )

    ~H"""
    <div
      :if={@digest.first_time_countries != [] or @digest.first_time_cities != []}
      class="card bg-base-200 shadow-xl mb-8"
    >
      <div class="card-body text-center items-center">
        <h2 class="card-title">
          <Icon.icon name="star" class="size-6" /> {t(
            @locale,
            "users.digests.show.first_time_visits",
            %{}
          )}
        </h2>
        <div :if={@digest.first_time_countries != []} class="mb-4">
          <h3 class="font-semibold mb-2">{t(@locale, "users.digests.show.new_countries", %{})}</h3>
          <div class="flex flex-wrap gap-2 justify-center">
            <span :for={country <- @digest.first_time_countries} class="badge badge-success badge-lg">{country}</span>
          </div>
        </div>
        <div :if={@digest.first_time_cities != []}>
          <h3 class="font-semibold mb-2">{t(@locale, "users.digests.show.new_cities", %{})}</h3>
          <div class="flex flex-wrap gap-2 justify-center">
            <span :for={city <- Enum.take(@digest.first_time_cities, 10)} class="badge badge-outline">{city}</span>
            <span :if={length(@digest.first_time_cities) > 10} class="badge badge-ghost">+{length(
              @digest.first_time_cities
            ) - 10} {t(@locale, "users.digests.show.more", %{})}</span>
          </div>
        </div>
      </div>
    </div>
    <div :if={@digest.monthly_distances != []} class="card bg-base-200 shadow-xl mb-8">
      <div class="card-body text-center items-center">
        <h2 class="card-title">
          <Icon.icon name="activity" class="size-6" /> {t(
            @locale,
            "users.digests.show.your_year_month_by_month",
            %{}
          )}
        </h2>
        <div class="w-full h-64 bg-base-100 rounded-lg p-4">
          <Chartkick.column_chart
            id="chart-1"
            height="250px"
            data={DigestFormat.monthly_chart(@locale, @digest.monthly_distances, @unit)}
            options={[
              suffix: " " <> @unit,
              xtitle: t(@locale, "users.digests.show.month", %{}),
              ytitle: t(@locale, "users.digests.show.distance", %{}),
              colors: YearCards.month_colors()
            ]}
          />
        </div>
      </div>
    </div>
    <div :if={@digest.top_countries != []} class="card bg-base-200 shadow-xl mb-8">
      <div class="card-body text-center items-center">
        <h2 class="card-title">
          <Icon.icon name="map-pin" class="size-6" /> {t(
            @locale,
            "users.digests.show.where_you_spent_the_most_time",
            %{}
          )}
        </h2>
        <div class="space-y-4 w-full">
          <div
            :for={{country, index} <- Enum.with_index(Enum.take(@digest.top_countries, 5))}
            class="flex justify-between items-center p-3 bg-base-100 rounded-lg"
          >
            <div class="flex items-center gap-3">
              <span class={"badge badge-lg #{Enum.at(@ranks, index)}"}>{index + 1}</span>
              <span class="font-semibold"><span class="mr-1"><Icon.country_flag
                name={country["name"]}
                table={@table}
              /></span> {country["name"]}</span>
            </div>
            <span class="text-gray-600">{DigestFormat.time_spent(@locale, country["minutes"])}</span>
          </div>
          <%= if @untracked > 0 do %>
            <div class="flex justify-between items-center p-3 bg-base-100 rounded-lg border-2 border-dashed border-gray-200">
              <div class="flex items-center gap-3">
                <span class="badge badge-lg badge-ghost">?</span>
                <span class="text-gray-500 italic">{t(
                  @locale,
                  "users.digests.show.no_tracking_data",
                  %{}
                )}</span>
              </div>
              <span class="text-gray-500">{t(@locale, "users.digests.show.day_count", %{
                count: round(@untracked)
              })}</span>
            </div>
            <p class="text-sm text-gray-500 mt-2 flex items-center justify-center gap-2">
              <Icon.icon name="lightbulb" class="size-6" /> {t(
                @locale,
                "users.digests.show.track_more_in",
                %{}
              )} {@digest.year + 1} {t(
                @locale,
                "users.digests.show.to_see_a_fuller_picture_of_your_travels",
                %{}
              )}
            </p>
          <% end %>
        </div>
      </div>
    </div>
    <div class="card bg-base-200 shadow-xl mb-8">
      <div class="card-body text-center items-center">
        <h2 class="card-title">
          <Icon.icon name="earth" class="size-6" /> {t(
            @locale,
            "users.digests.show.countries_cities",
            %{}
          )}
        </h2>
        <div class="space-y-4 w-full">
          <%= if @digest.toponyms != [] do %>
            <div :for={{country, index} <- Enum.with_index(@digest.toponyms)} class="space-y-2">
              <div class="flex justify-between items-center">
                <span class="font-semibold"><span class="mr-1"><Icon.country_flag
                  name={country["country"]}
                  table={@table}
                /></span> {country["country"]}</span>
                <span class="text-sm">{t(@locale, "users.digests.show.city_count", %{
                  count: DigestFormat.city_count(country)
                })}</span>
              </div>
              <progress
                class={"progress #{StatsFormat.progress_color(index)} w-full"}
                value={
                  StatsFormat.city_progress(
                    DigestFormat.city_count(country),
                    DigestFormat.max_cities(@digest.toponyms)
                  )
                }
                max="100"
              ></progress>
            </div>
          <% else %>
            <p class="text-gray-500">
              {t(@locale, "users.digests.show.no_location_data_available", %{})}
            </p>
          <% end %>
        </div>
      </div>
    </div>
    <div class="card bg-slate-800 text-white shadow-xl mb-8">
      <div class="card-body text-center items-center">
        <h2 class="card-title text-white">
          <Icon.icon name="trophy" class="size-6" /> {t(
            @locale,
            "users.digests.show.all_time_stats",
            %{}
          )}
        </h2>
        <div class="grid grid-cols-2 gap-4 mt-4">
          <div class="stat place-items-center">
            <div class="stat-title text-gray-400">
              {t(@locale, "users.digests.show.countries_visited", %{})}
            </div>
            <div class="stat-value text-white">{@digest.total_countries_all_time}</div>
          </div>
          <div class="stat place-items-center">
            <div class="stat-title text-gray-400">
              {t(@locale, "users.digests.show.cities_explored", %{})}
            </div>
            <div class="stat-value text-white">{@digest.total_cities_all_time}</div>
          </div>
        </div>
        <div class="stat place-items-center mt-2">
          <div class="stat-title text-gray-400">
            {t(@locale, "users.digests.show.total_distance", %{})}
          </div>
          <div class="stat-value text-white">
            {DigestFormat.distance_with_unit(@locale, @digest.total_distance_all_time, @unit)}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
