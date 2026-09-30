defmodule DawarichWeb.DigestsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  alias Dawarich.Digests
  alias DawarichWeb.{DigestFormat, Icon, StatsFormat}

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  def page(user, _params, %{locale: locale, now: now, self_hosted: self_hosted}) do
    context = Dawarich.Stats.context(user, now, self_hosted)

    Map.merge(Digests.index(user.id, context), %{
      page_title: t(locale, "users.digests.index.year_end_digests", %{}),
      unit: StatsFormat.unit(user.settings),
      generate: user.status == 1
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-screen-2xl mx-auto my-5 px-4">
      <div class="page-header-row mb-6">
        <h1 class="text-3xl font-bold flex items-center gap-2">
          <Icon.icon name="earth" class="size-6" /> {t(
            @locale,
            "users.digests.index.year_end_digests",
            %{}
          )}
        </h1>
        <div :if={@available_years != [] and @generate} class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-primary"><Icon.icon
            name="calendar-plus-2"
            class="size-6"
          /> {t(@locale, "users.digests.index.generate_digest", %{})}</label>
          <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52">
            <li :for={year <- @available_years}>
              <a data-turbo-method="post" class="text-base" href={"/digests?year=#{year}"}>{year}</a>
            </li>
          </ul>
        </div>
      </div>
      <%= if @digests == [] do %>
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body text-center py-12">
            <h2 class="text-xl font-semibold mb-2 flex items-center justify-center gap-2">
              <Icon.icon name="earth" class="size-6" />{t(
                @locale,
                "users.digests.index.no_year_end_digests_yet",
                %{}
              )}
            </h2>
            <p class="text-gray-500 mb-4">
              {t(
                @locale,
                "users.digests.index.year_end_digests_are_automatically_generated_on_january_1st_each",
                %{}
              )}
              <%= if @available_years != [] and @generate do %>
                <br />{t(
                  @locale,
                  "users.digests.index.or_you_can_manually_generate_one_for_a_previous_year",
                  %{}
                )}
              <% end %>
            </p>
          </div>
        </div>
      <% else %>
        <div class="grid grid-cols-1 gap-6">
          <div
            :for={digest <- @digests}
            class="card bg-base-200 shadow-xl hover:shadow-2xl transition-shadow"
          >
            <div class="card-body">
              <h2 class="card-title text-2xl justify-between">
                <a class="hover:text-primary" href={"/digests/#{digest.year}"}>{digest.year}</a>
                <span :if={digest.sharing_enabled} class="badge badge-success badge-sm">{t(
                  @locale,
                  "users.digests.index.shared",
                  %{}
                )}</span>
              </h2>
              <div class="stats stats-vertical shadow bg-base-100 mt-4 text-center">
                <div class="stat">
                  <div class="stat-title">{t(@locale, "users.digests.index.distance", %{})}</div>
                  <div class="stat-value text-primary text-lg">
                    {DigestFormat.distance_with_unit(@locale, digest.distance, @unit)}
                  </div>
                </div>
                <div class="stat">
                  <div class="stat-value text-secondary text-lg">
                    {Digests.countries_count(digest.toponyms)}
                  </div>
                  <div class="stat-title">{t(@locale, "users.digests.index.countries", %{})}</div>
                  <div
                    :if={digest.first_time_countries != []}
                    class="stat-desc text-success flex items-center gap-1 justify-center"
                  >
                    <Icon.icon name="star" class="size-6" /> {length(digest.first_time_countries)} {t(
                      @locale,
                      "users.digests.index.new",
                      %{}
                    )}
                  </div>
                </div>
                <div class="stat">
                  <div class="stat-value text-accent text-lg">
                    {Digests.cities_count(digest.toponyms)}
                  </div>
                  <div class="stat-title">{t(@locale, "users.digests.index.cities", %{})}</div>
                  <div
                    :if={digest.first_time_cities != []}
                    class="stat-desc text-success flex items-center gap-1 justify-center"
                  >
                    <Icon.icon name="star" class="size-6" /> {length(digest.first_time_cities)} {t(
                      @locale,
                      "users.digests.index.new",
                      %{}
                    )}
                  </div>
                </div>
              </div>
              <div class="card-actions justify-end mt-4">
                <a class="btn btn-primary btn-sm" href={"/digests/#{digest.year}"}>{t(
                  @locale,
                  "users.digests.index.view_details",
                  %{}
                )}</a>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
