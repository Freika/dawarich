defmodule DawarichWeb.IntegrationForms do
  @moduledoc false
  use DawarichWeb, :html

  @jobs %{"airtrail" => "start_airtrail_import", "teslamate" => "start_teslamate_sync"}

  attr :service, :string, required: true
  attr :form, :any, required: true
  slot :inner_block, required: true

  def form_head(assigns) do
    ~H"""
    <form
      id="native-integration-settings"
      action="/settings/integrations"
      accept-charset="UTF-8"
      method="post"
      phx-change="change"
      phx-submit="save"
    >
      <input type="hidden" name="_method" value="patch" />
      <input type="hidden" name="authenticity_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="service" id="service" value={@service} />
      {render_slot(@inner_block)}
    </form>
    """
  end

  attr :form, :any, required: true
  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :label_class, :string, default: "label"
  attr :span, :boolean, default: true
  attr :placeholder, :string, default: nil
  attr :autocomplete, :string, default: nil

  def secret_field(assigns) do
    ~H"""
    <label class={@label_class} for={"settings_" <> @key}>
      <span :if={@span} class="label-text font-medium">{@label}</span>
      <%= if not @span do %>
        {@label}
      <% end %>
    </label>
    <input
      type="password"
      name={"settings[#{@key}]"}
      id={"settings_" <> @key}
      value={secret_display(@form[@key].value)}
      class="input input-bordered w-full"
      placeholder={@placeholder}
      autocomplete={@autocomplete}
      phx-update="ignore"
    />
    """
  end

  def save(assigns) do
    ~H"""
    <input
      type="submit"
      name="commit"
      value={t(@locale, "settings.integrations.index.save_test_connection", %{})}
      class="btn btn-primary"
      phx-disable-with={t(@locale, "settings.integrations.index.save_test_connection", %{})}
    />
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
        <form
          class="button_to"
          method="post"
          action={"/settings/background_jobs?job_name=" <> job(@service)}
          phx-submit="sync"
        >
          <button
            id="native-integration-sync"
            type="submit"
            class="btn btn-primary btn-sm"
            phx-disable-with={t(@locale, "settings.integrations.index.sync_now", %{})}
            disabled={MapSet.member?(@queued, @service) && "disabled"}
          >{t(@locale, "settings.integrations.index.sync_now", %{})}</button>
          <input type="hidden" name="authenticity_token" value={Plug.CSRFProtection.get_csrf_token()} />
        </form>
      </div>
    </div>
    """
  end

  defp job(service), do: Map.fetch!(@jobs, service)

  def secret_display("********"), do: "********"
  def secret_display(_), do: nil
end
