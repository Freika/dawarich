defmodule DawarichWeb.IntegrationPanes do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1, brand: 1]

  @brands ~w(immich photoprism airtrail)
  @lucide %{"teslamate" => "car", "trek" => "map-pin-check"}
  @placeholders %{
    "immich" => "http://192.168.0.1:2283",
    "photoprism" => "http://192.168.0.1:2342",
    "airtrail" => "https://airtrail.example.com",
    "teslamate" => "https://teslamateapi.example.com"
  }

  attr :service, :string, required: true
  attr :css, :string, required: true

  def service_icon(assigns) do
    ~H"""
    <.brand :if={@service in brands()} name={@service} class={@css <> " shrink-0"} />
    <.icon
      :if={@service not in brands()}
      name={lucide(@service)}
      class={@css <> " shrink-0 text-base-content/60"}
    />
    """
  end

  defp brands, do: @brands
  defp lucide(service), do: @lucide[service]

  attr :locale, :string, required: true
  attr :status, :string, default: nil

  def status_icon(%{status: "connected"} = assigns) do
    ~H"""
    <span
      class="tooltip tooltip-left"
      data-tip={t(@locale, "settings.integrations.index.status_connected", %{})}
    ><.icon name="circle-check" class="size-4 text-success" /></span>
    """
  end

  def status_icon(%{status: "failed"} = assigns) do
    ~H"""
    <span
      class="tooltip tooltip-left"
      data-tip={t(@locale, "settings.integrations.index.status_failed", %{})}
    ><.icon name="circle-alert" class="size-4 text-warning" /></span>
    """
  end

  def status_icon(assigns), do: ~H""

  attr :service, :string, required: true
  attr :locale, :string, required: true
  attr :form, :any, required: true
  attr :queued, :any, default: MapSet.new()
  attr :synced, :string, default: nil

  def pane(%{service: service} = assigns) when service in ~w(immich photoprism) do
    ~H"""
    <div class="rounded-box border border-base-content/10 bg-base-200 max-w-3xl">
      <.form_head service={@service} form={@form}>
        <div class="card-body space-y-5">
          <.heading service={@service} locale={@locale} />
          <.url_field service={@service} locale={@locale} form={@form} />
          <.key_field service={@service} locale={@locale} form={@form}>
            <%= if @service == "immich" do %>
              {t(
                @locale,
                "settings.integrations.index.found_in_your_immich_admin_panel_under_api_settings_required",
                %{}
              )} <code class="text-xs">{t(@locale, "settings.integrations.index.asset_read", %{})}</code>, <code class="text-xs">{t(@locale, "settings.integrations.index.asset_view", %{})}</code>{t(
                @locale,
                "settings.integrations.index.and",
                %{}
              )}
              <code class="text-xs">{t(@locale, "settings.integrations.index.asset_update", %{})}</code> {t(
                @locale,
                "settings.integrations.index.for_photo_enrichment",
                %{}
              )}
            <% else %>
              {t(
                @locale,
                "settings.integrations.index.found_in_your_photoprism_settings_under_library",
                %{}
              )}
            <% end %>
          </.key_field>
          <.ssl_toggle service={@service} locale={@locale} form={@form}>
            <.icon name="triangle-alert" class="size-6" />
          </.ssl_toggle>
          <div :if={@service == "immich"} class="flex flex-wrap items-center gap-2">
            <button
              name="refresh_photos_cache"
              type="submit"
              value="1"
              class="btn btn-sm btn-outline"
              phx-disable-with={t(@locale, "settings.integrations.index.refresh_photo_cache", %{})}
            >{t(
              @locale,
              "settings.integrations.index.refresh_photo_cache",
              %{}
            )}</button>
            <span class="label-text-alt text-base-content/60">{t(
              @locale,
              "settings.integrations.index.clears_cached_photo_metadata_and_thumbnails_for_all_integrations",
              %{}
            )}</span>
          </div>
          <div class="card-actions"><.save locale={@locale} /></div>
        </div>
      </.form_head>
    </div>
    """
  end

  def pane(%{service: "airtrail"} = assigns), do: DawarichWeb.AirtrailPane.pane(assigns)
  def pane(%{service: "teslamate"} = assigns), do: DawarichWeb.TeslamatePane.pane(assigns)

  attr :service, :string, required: true
  attr :form, :any, required: true
  slot :inner_block, required: true

  def form_head(assigns) do
    ~H"""
    <.form for={@form} id="integration-settings" phx-change="change" phx-submit="save">
      {render_slot(@inner_block)}
    </.form>
    """
  end

  def heading(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.icon name="link" class="size-6 shrink-0" />
      <h2 class="text-xl font-semibold">
        {t(@locale, "settings.integrations.index.#{@service}_integration", %{})}
      </h2>
    </div>
    """
  end

  def url_field(assigns) do
    assigns = assign(assigns, :placeholder, @placeholders[assigns.service])

    ~H"""
    <div class="form-control w-full max-w-md">
      <label class="label" for={"settings_#{@service}_url"}><span class="label-text font-medium">{t(
        @locale,
        "settings.integrations.index.#{@service}_url",
        %{}
      )}</span></label>
      <input
        value={@form[@service <> "_url"].value}
        class="input input-bordered w-full"
        placeholder={@placeholder}
        type="url"
        name={"settings[#{@service}_url]"}
        id={"settings_#{@service}_url"}
      />
      <span class="label-text-alt mt-1 text-base-content/60">{t(
        @locale,
        "settings.integrations.index.the_base_url_of_your_#{@service}_instance#{if @service == "airtrail", do: "_your_flights_are", else: ""}",
        %{}
      )}</span>
    </div>
    """
  end

  attr :service, :string, required: true
  attr :locale, :string, required: true
  attr :form, :any, required: true
  slot :inner_block, required: true

  def key_field(assigns) do
    ~H"""
    <div class="form-control w-full max-w-md">
      <DawarichWeb.CoreComponents.input
        field={@form[@service <> "_api_key"]}
        type="password"
        display={secret_display(@form[@service <> "_api_key"].value)}
        phx-update="ignore"
        label_class="label font-medium"
        placeholder={t(@locale, "settings.integrations.index.xxxxxxxxxxxxxx", %{})}
        label={t(@locale, "settings.integrations.index.#{@service}_api_key", %{})}
      />
      <span class="label-text-alt mt-1 text-base-content/60">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  attr :service, :string, required: true
  attr :locale, :string, required: true
  attr :form, :any, required: true
  slot :inner_block, required: true

  def ssl_toggle(assigns) do
    assigns =
      assign(
        assigns,
        :on,
        Dawarich.UserSettings.cast(
          assigns.form[assigns.service <> "_skip_ssl_verification"].value
        ) == true
      )

    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input name={"settings[#{@service}_skip_ssl_verification]"} type="hidden" value="0" /><input
          class="toggle toggle-warning"
          type="checkbox"
          value="1"
          checked={@on && "checked"}
          name={"settings[#{@service}_skip_ssl_verification]"}
          id={"settings_#{@service}_skip_ssl_verification"}
        />
        <span class="label-text">{t(
          @locale,
          "settings.integrations.index.skip_ssl_certificate_verification_self_signed_certificates",
          %{}
        )}</span>
      </label>
      <div
        id={"#{@service}-ssl-warning"}
        class={"alert alert-warning mt-2 #{unless @on, do: "hidden"}"}
      >
        {render_slot(@inner_block)}
        <span>
          <strong>{t(@locale, "settings.integrations.index.security_warning", %{})}</strong> {t(
            @locale,
            "settings.integrations.index.disabling_ssl_verification_makes_your_connection_vulnerable_to_man_in",
            %{}
          )}
        </span>
      </div>
    </div>
    """
  end

  def save(assigns) do
    ~H"""
    <button
      type="submit"
      class="btn btn-primary"
      phx-disable-with={t(@locale, "settings.integrations.index.save_test_connection", %{})}
    >{t(@locale, "settings.integrations.index.save_test_connection", %{})}</button>
    """
  end

  attr :locale, :string, required: true
  attr :service, :string, required: true
  attr :queued, :any, default: MapSet.new()
  slot :inner_block, required: true

  def sync_row(assigns) do
    ~H"""
    <div class="border-t border-base-content/10 px-8 py-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>{render_slot(@inner_block)}</div>
        <button
          id="integration-sync"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="sync"
          phx-disable-with={t(@locale, "settings.integrations.index.sync_now", %{})}
          disabled={MapSet.member?(@queued, @service)}
        >{t(@locale, "settings.integrations.index.sync_now", %{})}</button>
      </div>
    </div>
    """
  end

  def secret_display("********"), do: "********"
  def secret_display(_value), do: ""
end
