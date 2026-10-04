defmodule DawarichWeb.AdminSettingField do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  attr :locale, :string, required: true
  attr :field, :map, required: true

  def field(assigns) do
    field = assigns.field

    assigns =
      assign(assigns,
        id: "instance_settings_" <> field.key,
        name: "instance_settings[#{field.key}]",
        hint: hint(assigns.locale, field),
        placeholder: placeholder(assigns.locale, field),
        type: type(field.kind)
      )

    ~H"""
    <div
      class="grid gap-x-8 gap-y-2 py-4 sm:grid-cols-[minmax(0,13rem)_minmax(0,1fr)] sm:items-start"
      data-testid={"instance-setting-" <> @field.key}
    >
      <div class="min-w-0 sm:pt-3">
        <label for={@id} class="block text-sm font-medium">{t(
          @locale,
          "admin.settings.show.fields." <> @field.key,
          %{}
        )}</label>
        <code class="mt-0.5 block text-xs text-base-content/70 [overflow-wrap:anywhere]">{@field.env_var}</code>
      </div>
      <div class="min-w-0 space-y-2">
        <%= if @field.kind == :boolean do %>
          <div class="flex items-center sm:min-h-12">
            <input :if={@field.hidden_false} type="hidden" name={@name} value="false" />
            <input
              type="checkbox"
              id={@id}
              name={@name}
              value="true"
              class="toggle toggle-primary"
              checked={@field.value not in [nil, false] or @field.locked_on}
              disabled={@field.disabled}
              aria-describedby={@hint && @id <> "_hint"}
            />
          </div>
        <% else %>
          <input
            type={@type}
            id={@id}
            name={@name}
            value={@field.display || ""}
            autocomplete="off"
            step={@field.kind == :float && "any"}
            min={@field.kind == :float && "0"}
            inputmode={@field.kind == :float && "decimal"}
            class={"input input-bordered w-full disabled:border-base-content/10 disabled:bg-base-100 " <> if(@field.kind == :float, do: "tabular-nums", else: "")}
            placeholder={@placeholder}
            disabled={@field.pinned}
            aria-describedby={@hint && @id <> "_hint"}
          />
        <% end %>
        <p :if={@field.pinned} class="flex items-center gap-1.5 text-xs text-base-content/70">
          <.icon name="lock" class="size-3.5 shrink-0" />
          <span class="min-w-0 [overflow-wrap:anywhere]">{t(
            @locale,
            "admin.settings.show.pinned_hint",
            %{variable: @field.env_var}
          )}</span>
        </p>
        <p :if={@field.unreadable and not @field.pinned} class="flex items-start gap-1.5 text-xs">
          <.icon name="triangle-alert" class="size-3.5 shrink-0 mt-px text-warning" />
          <span class="min-w-0 [text-wrap:pretty]">{t(
            @locale,
            "admin.settings.show.unreadable_secret",
            %{}
          )}</span>
        </p>
        <p :if={@hint} id={@id <> "_hint"} class="text-xs text-base-content/70 [text-wrap:pretty]">
          {@hint}
        </p>
        <label
          :if={@field.clear}
          class="flex cursor-pointer items-center gap-2 text-xs text-base-content/70"
          for={@id <> "_clear"}
        >
          <input
            type="checkbox"
            id={@id <> "_clear"}
            class="checkbox checkbox-xs"
            name={"instance_settings_clear[#{@field.key}]"}
            value="1"
          />
          <span>{t(@locale, "admin.settings.show.clear_secret", %{})}</span>
        </label>
      </div>
    </div>
    """
  end

  defp type(:secret), do: "password"
  defp type(:float), do: "number"
  defp type(_), do: "text"

  defp hint(locale, field) do
    key =
      cond do
        field.key in ~w(photon_api_host nominatim_api_host) -> "fields.host_hint"
        field.locked_on -> "geocoding.https_locked"
        field.key == "reverse_geocoding_rps" -> "fields.rps_hint"
        field.key == "store_geodata" -> "fields.store_geodata_hint"
        field.kind == :secret and field.present and not field.pinned -> "fields.api_key_keep_hint"
        true -> nil
      end

    if key, do: t(locale, "admin.settings.show." <> key, %{})
  end

  defp placeholder(_locale, %{kind: :secret, present: true, pinned: true}), do: "••••••••"

  defp placeholder(locale, %{kind: :secret, present: true}),
    do: t(locale, "admin.settings.show.secret_set", %{})

  defp placeholder(_locale, _field), do: ""
end
