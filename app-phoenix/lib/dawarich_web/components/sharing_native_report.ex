defmodule DawarichWeb.SharingNativeReport do
  @moduledoc false
  use DawarichWeb, :html
  attr :resource, :map, required: true
  attr :page, :map, required: true
  attr :locale, :string, required: true

  def form(assigns) do
    settings = assigns.page[:settings] || %{}
    enabled = assigns.page[:enabled] || settings["enabled"] == true

    scope =
      if assigns.resource.type == :digest, do: "users.digests.show", else: "shared.sharing_modal"

    assigns =
      assign(assigns,
        enabled: enabled,
        expiration:
          settings["expiration"] || if(assigns.resource.type == :month, do: "1h", else: "24h"),
        scope: scope,
        url: url(assigns.resource, assigns.page.uuid)
      )

    ~H"""
    <form id="report-sharing-form" phx-submit="report_sharing_update" class="space-y-4 min-w-0">
      <label class="flex flex-wrap items-center gap-3 min-w-0">
        <input type="hidden" name="enabled" value="0" />
        <input
          type="checkbox"
          name="enabled"
          value="1"
          checked={@enabled}
          class="toggle toggle-primary"
        />
        <span class="min-w-0">{t(
          @locale,
          if(@resource.type == :achievement,
            do: "achievements.ui.enable_sharing",
            else: @scope <> ".enable_public_access"
          ),
          %{}
        )}</span>
      </label>
      <label :if={@resource.type != :achievement} class="form-control min-w-0">
        <span>{t(@locale, @scope <> ".link_expiration", %{})}</span>
        <select name="expiration" class="select select-bordered w-full min-w-0">
          <option
            :for={
              {label, value} <- [
                {"1 hour", "1h"},
                {"12 hours", "12h"},
                {"24 hours", "24h"},
                {"1 week", "1w"},
                {"1 month", "1m"}
              ]
            }
            value={value}
            selected={value == @expiration}
          >
            {label}
          </option>
        </select>
      </label>
      <button
        type="submit"
        class="btn btn-primary h-auto whitespace-normal"
        phx-disable-with={t(@locale, "javascript.common.confirm", %{})}
      >{t(@locale, "javascript.common.confirm", %{})}</button>
    </form>
    <div :if={@enabled and @url} class="flex flex-wrap gap-3 mt-4 min-w-0">
      <a data-public-share href={@url} class="link min-w-0 [overflow-wrap:anywhere]">{t(
        @locale,
        "achievements.ui.public_link",
        %{}
      )}</a>
      <button
        id="report-share-copy"
        type="button"
        phx-hook="Clipboard"
        data-clipboard-text={@url}
        data-clipboard-url="true"
        data-copied-label={t(@locale, "javascript.messages.copied_to_clipboard", %{})}
        data-failed-label={t(@locale, "javascript.messages.failed_to_copy_please_copy_manually", %{})}
        data-status-id="report-copy-status"
        class="btn btn-outline h-auto whitespace-normal"
      >{t(@locale, "shared.sharing_link.copy", %{})}</button>
      <span id="report-copy-status" role="status" aria-live="polite"></span>
    </div>
    """
  end

  defp url(_, nil), do: nil

  defp url(%{type: type}, uuid),
    do:
      "/shared/" <>
        %{month: "month", digest: "digest", achievement: "achievements"}[type] <> "/" <> uuid
end
