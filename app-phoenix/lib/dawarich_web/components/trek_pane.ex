defmodule DawarichWeb.TrekPane do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.IntegrationPanes, only: [service_icon: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.LocalizedDate

  attr :locale, :string, required: true
  attr :sources, :list, required: true
  attr :rails_csrf_token, :string, default: nil

  def pane(assigns) do
    ~H"""
    <div class="space-y-6 max-w-3xl">
      <div
        id="trek-source-form"
        class="rounded-box border border-base-content/10 bg-base-200"
        phx-update="ignore"
      >
        <form data-turbo="false" action="/settings/trek_sources" accept-charset="UTF-8" method="post">
          <input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
          <div class="card-body space-y-5">
            <div class="flex items-center gap-3">
              <.service_icon service="trek" css="size-6" />
              <div>
                <h2 class="text-xl font-semibold">
                  {t(@locale, "settings.integrations.trek.title", %{})}
                </h2>
                <p class="text-sm text-base-content/60">
                  {t(@locale, "settings.integrations.trek.subtitle", %{})}
                </p>
              </div>
            </div>
            <div class="form-control w-full max-w-md">
              <label class="label" for="trip_source_base_url"><span class="label-text font-medium">{t(
                @locale,
                "settings.integrations.trek.trek_url",
                %{}
              )}</span></label>
              <input
                class="input input-bordered w-full"
                placeholder="https://trek.example.com"
                required="required"
                type="url"
                name="trip_source[base_url]"
                id="trip_source_base_url"
              />
              <span class="label-text-alt mt-1 text-base-content/60">{t(
                @locale,
                "settings.integrations.trek.cloud_notice",
                %{}
              )}</span>
            </div>
            <div class="form-control w-full max-w-md">
              <label class="label" for="trip_source_api_key"><span class="label-text font-medium">{t(
                @locale,
                "settings.integrations.trek.api_key",
                %{}
              )}</span></label>
              <input
                class="input input-bordered w-full"
                placeholder="trek_…"
                required="required"
                type="password"
                name="trip_source[api_key]"
                id="trip_source_api_key"
              />
              <span class="label-text-alt mt-1 text-base-content/60">{t(
                @locale,
                "settings.integrations.trek.api_key_help",
                %{}
              )}</span>
            </div>
            <div class="card-actions">
              <input
                type="submit"
                name="commit"
                value={t(@locale, "settings.integrations.trek.connect", %{})}
                class="btn btn-primary"
                data-disable-with={t(@locale, "settings.integrations.trek.connect", %{})}
              />
            </div>
          </div>
        </form>
      </div>

      <div :for={source <- @sources} class="rounded-box border border-base-content/10 bg-base-200">
        <div class="card-body gap-4">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 class="font-semibold">{source.base_url}</h3>
              <p class="text-sm text-base-content/60">{sync_line(@locale, source)}</p>
              <p :if={Ruby.present?(source.last_error)} class="text-sm text-warning mt-1">
                {source.last_error}
              </p>
            </div>
            <span class={"badge #{if source.active, do: "badge-success", else: "badge-warning"}"}>{source.status}</span>
          </div>
          <div class="flex flex-wrap gap-2">
            <%= cond do %>
              <% source.active and not source.importing -> %>
                <a
                  class="btn btn-primary btn-sm"
                  href={"/settings/trek_sources/#{source.id}/select_trips"}
                >{t(@locale, "settings.integrations.trek.choose_trips", %{})}</a>
                <form
                  class="button_to"
                  method="post"
                  action={"/settings/trek_sources/#{source.id}/sync"}
                >
                  <button class="btn btn-outline btn-sm" type="submit">{t(
                    @locale,
                    "settings.integrations.trek.sync_now",
                    %{}
                  )}</button><input
                    :if={@rails_csrf_token}
                    type="hidden"
                    name="authenticity_token"
                    value={@rails_csrf_token}
                  />
                </form>
              <% source.status == "disabled" -> %>
                <a class="btn btn-outline btn-sm" href="#trek-source-form">{t(
                  @locale,
                  "settings.integrations.trek.reconnect",
                  %{}
                )}</a>
              <% true -> %>
            <% end %>
            <form class="button_to" method="post" action={"/settings/trek_sources/#{source.id}"}>
              <input type="hidden" name="_method" value="delete" /><button
                class="btn btn-ghost btn-sm text-error"
                data-turbo-confirm={
                  t(@locale, "settings.integrations.trek.disconnect_confirmation", %{})
                }
                type="submit"
              >{t(@locale, "settings.integrations.trek.disconnect", %{})}</button><input
                :if={@rails_csrf_token}
                type="hidden"
                name="authenticity_token"
                value={@rails_csrf_token}
              />
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp sync_line(locale, %{importing: true}),
    do: t(locale, "settings.integrations.trek.importing_trips", %{})

  defp sync_line(locale, %{synced: %NaiveDateTime{} = synced}),
    do:
      t(locale, "settings.integrations.trek.last_synced", %{
        time: LocalizedDate.time(locale, synced, "long")
      })

  defp sync_line(locale, _source), do: t(locale, "settings.integrations.trek.not_synced_yet", %{})
end
