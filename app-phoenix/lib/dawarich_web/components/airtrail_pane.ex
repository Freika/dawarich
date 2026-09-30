defmodule DawarichWeb.AirtrailPane do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  import DawarichWeb.IntegrationPanes,
    only: [
      form_head: 1,
      heading: 1,
      url_field: 1,
      key_field: 1,
      ssl_toggle: 1,
      save: 1,
      sync_row: 1
    ]

  alias Dawarich.UserSettings
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  attr :service, :string, required: true
  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :synced, :string, default: nil

  def pane(assigns) do
    ~H"""
    <div class="rounded-box border border-base-content/10 bg-base-200 max-w-3xl">
      <.form_head service="airtrail" rails_csrf_token={@rails_csrf_token}>
        <div class="card-body space-y-5">
          <.heading service="airtrail" locale={@locale} />
          <.url_field service="airtrail" locale={@locale} user={@user} />
          <.key_field service="airtrail" locale={@locale} user={@user}>
            {t(
              @locale,
              "settings.integrations.index.create_an_api_key_in_airtrail_under_settings_rarr_security",
              %{}
            )}
          </.key_field>
          <.ssl_toggle service="airtrail" locale={@locale} user={@user}>
            <.icon name="triangle-alert" class="size-6" />
          </.ssl_toggle>
          <p :if={@synced} class="label-text-alt text-base-content/60">
            {t(@locale, "settings.integrations.index.last_synced", %{})} {@synced}
          </p>
          <div class="card-actions"><.save locale={@locale} /></div>
        </div>
      </.form_head>
      <.sync_row
        :if={Ruby.present?(UserSettings.value(@user, "airtrail_url"))}
        locale={@locale}
        job="start_airtrail_import"
        rails_csrf_token={@rails_csrf_token}
      >
        <h3 class="font-semibold flex items-center gap-2">
          <.icon name="plane" class="size-5 text-primary" /> {t(
            @locale,
            "settings.integrations.index.sync_airtrail_flights",
            %{}
          )}
        </h3>
        <span class="label-text-alt text-base-content/60">{t(
          @locale,
          "settings.integrations.index.flights_also_sync_automatically_once_a_day",
          %{}
        )}</span>
      </.sync_row>
    </div>
    """
  end
end
