defmodule DawarichWeb.FamilyNativeRequests do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.FamilyNativeControls

  def request(assigns) do
    ~H"""
    <section
      id="family-request-shell"
      class="container mx-auto max-w-lg py-8 min-w-0 [overflow-wrap:anywhere]"
    >
      <FamilyNativeControls.errors errors={@errors} />
      <div class="card bg-base-200 p-5 space-y-4">
        <h1 class="text-2xl font-semibold">{s(@locale, "location_request")}</h1>
        <dl class="space-y-4">
          <div>
            <dt>{s(@locale, "requested_by")}</dt><dd>{@page.request.requester_email}</dd>
          </div>
          <div>
            <dt>{s(@locale, "requested")}</dt><dd>
              {t(@locale, "common.time_ago", %{
                time: DawarichWeb.TimeAgo.words(@locale, @page.request.created_at, @now)
              })}
            </dd>
          </div>
          <div :if={@page.request.display == :pending}>
            <dt>{s(@locale, "expires")}</dt><dd>
              {t(@locale, "common.time_from_now", %{
                time: DawarichWeb.TimeAgo.words(@locale, @page.request.expires_at, @now)
              })}
            </dd>
          </div>
        </dl>
        <%= if @page.request.display == :pending do %>
          <form id="native-family-request" phx-submit="family_respond" class="space-y-4">
            <input type="hidden" name="decision" value="accept" />
            <label for="native-request-duration" class="label label-text">{s(
              @locale,
              "share_location_for"
            )}</label>
            <select id="native-request-duration" name="duration" class="select select-bordered w-full">
              <option :for={{value, key} <- durations()} value={value} selected={value == "24h"}>
                {s(@locale, key)}
              </option>
            </select>
            <button
              type="submit"
              class="btn btn-primary w-full h-auto whitespace-normal"
              phx-disable-with={s(@locale, "accept_share_location")}
            >{s(@locale, "accept_share_location")}</button>
          </form>
          <button
            type="button"
            class="btn btn-outline btn-warning w-full h-auto whitespace-normal"
            phx-click="family_respond"
            phx-value-decision="decline"
          >{s(@locale, "decline")}</button>
        <% else %>
          <span data-request-status={@page.request.display} class="badge badge-lg h-auto">{s(
            @locale,
            to_string(@page.request.display)
          )}</span>
          <p :if={@page.request.responded_at}>
            {s(@locale, "responded")} {t(@locale, "common.time_ago", %{
              time: DawarichWeb.TimeAgo.words(@locale, @page.request.responded_at, @now)
            })}
          </p>
        <% end %>
        <a href="/family" class="btn btn-ghost h-auto whitespace-normal">{s(@locale, "back_to_family")}</a>
      </div>
      <FamilyNativeControls.confirmation confirmation={@confirmation} page={@page} locale={@locale} />
    </section>
    """
  end

  defp s(locale, key), do: t(locale, "family.location_requests.show." <> key, %{})

  defp durations,
    do: [
      {"1h", "hour"},
      {"6h", "hours"},
      {"12h", "hours_2"},
      {"24h", "hours_3"},
      {"permanent", "permanently"}
    ]
end
