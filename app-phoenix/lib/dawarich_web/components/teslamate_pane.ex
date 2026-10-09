defmodule DawarichWeb.TeslamatePane do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.IntegrationPanes,
    only: [form_head: 1, heading: 1, ssl_toggle: 1, save: 1, sync_row: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  attr :service, :string, required: true
  attr :locale, :string, required: true
  attr :form, :any, required: true
  attr :queued, :any, default: MapSet.new()
  attr :synced, :string, default: nil

  def pane(assigns) do
    ~H"""
    <div class="rounded-box border border-base-content/10 bg-base-200 max-w-3xl">
      <.form_head service="teslamate" form={@form}>
        <div class="card-body space-y-5">
          <.heading service="teslamate" locale={@locale} />
          <div class="form-control w-full max-w-md">
            <label class="label" for="settings_teslamate_url"><span class="label-text font-medium">{t(
              @locale,
              "settings.integrations.index.teslamate_url",
              %{}
            )}</span></label>
            <input
              value={@form["teslamate_url"].value}
              class="input input-bordered w-full"
              placeholder="https://teslamateapi.example.com"
              type="url"
              name="settings[teslamate_url]"
              id="settings_teslamate_url"
            />
            <span class="label-text-alt mt-1 text-base-content/60">
              {t(
                @locale,
                "settings.integrations.index.the_base_url_of_your_teslamateapi_instance",
                %{}
              )}
              <a
                target="_blank"
                rel="noopener"
                class="link"
                href="https://github.com/tobiasehlert/teslamateapi#how-to-run-it"
              >{t(@locale, "settings.integrations.index.teslamate_setup_guide", %{})}</a>
            </span>
          </div>
          <div class="grid gap-4 md:grid-cols-2">
            <div class="form-control w-full">
              <label class="label label-text font-medium" for="settings_teslamate_username">{t(
                @locale,
                "settings.integrations.index.teslamate_username",
                %{}
              )}</label>
              <input
                value={@form["teslamate_username"].value}
                class="input input-bordered w-full"
                autocomplete="username"
                type="text"
                name="settings[teslamate_username]"
                id="settings_teslamate_username"
              />
            </div>
            <div class="form-control w-full">
              <label class="label label-text font-medium" for="settings_teslamate_password">{t(
                @locale,
                "settings.integrations.index.teslamate_password",
                %{}
              )}</label>
              <DawarichWeb.CoreComponents.input
                field={@form["teslamate_password"]}
                type="password"
                display={@form["teslamate_password"].value}
                label={t(@locale, "settings.integrations.index.teslamate_password", %{})}
              />
            </div>
          </div>
          <div class="form-control w-full max-w-md">
            <label class="label label-text font-medium" for="settings_teslamate_api_token">{t(
              @locale,
              "settings.integrations.index.teslamate_api_token",
              %{}
            )}</label>
            <DawarichWeb.CoreComponents.input
              field={@form["teslamate_api_token"]}
              type="password"
              display={@form["teslamate_api_token"].value}
              label={t(@locale, "settings.integrations.index.teslamate_api_token", %{})}
            />
            <span class="label-text-alt mt-1 text-base-content/60">{t(
              @locale,
              "settings.integrations.index.teslamate_authentication_help",
              %{}
            )}</span>
          </div>
          <.ssl_toggle service="teslamate" locale={@locale} form={@form}>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-6 w-6 shrink-0 stroke-current"
              fill="none"
              viewBox="0 0 24 24"
            ><path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            /></svg>
          </.ssl_toggle>
          <div class="card-actions"><.save locale={@locale} /></div>
          <p :if={@synced} class="label-text-alt text-base-content/60">
            {t(@locale, "settings.integrations.index.last_synced", %{})}
            {@synced}
          </p>
        </div>
      </.form_head>
      <.sync_row
        :if={Ruby.present?(@form["teslamate_url"].value)}
        locale={@locale}
        service="teslamate"
        queued={@queued}
      >
        <h3 class="font-semibold">
          {t(@locale, "settings.integrations.index.sync_teslamate_drives", %{})}
        </h3>
        <span class="label-text-alt text-base-content/60">{t(
          @locale,
          "settings.integrations.index.teslamate_sync_help",
          %{}
        )}</span>
      </.sync_row>
    </div>
    """
  end
end
