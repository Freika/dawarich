defmodule DawarichWeb.AuthFeatures do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :kind, :string, required: true

  def list(assigns) do
    {tag, scope, items} =
      case assigns.kind do
        "sign_in" ->
          {"ul", "devise.sessions.new.benefits",
           [
             {"map", "map"},
             {"import", "file-up"},
             {"stats", "chart-column"},
             {"privacy", "shield-check"}
           ]}

        "sign_up" ->
          {"ol", "devise.registrations.new.steps",
           [{"account", "user"}, {"mobile_app", "smartphone"}, {"import", "file-up"}]}
      end

    assigns = assign(assigns, tag: tag, scope: scope, items: items)

    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class="w-full max-w-sm mx-auto space-y-6 lg:max-w-md lg:mx-0 lg:col-start-1 lg:row-start-2 lg:pt-4"
    >
      <li :for={{key, icon} <- @items} class="flex gap-4">
        <DawarichWeb.Icon.icon name={icon} class="w-5 h-5 mt-0.5 shrink-0 text-base-content/70" />
        <div>
          <h2 class="font-semibold text-base-content">
            {t(@locale, @scope <> "." <> key <> ".title", %{})}
          </h2>
          <p class="mt-1 text-sm text-base-content/70">
            {t(@locale, @scope <> "." <> key <> ".body", %{})}
          </p>
        </div>
      </li>
    </.dynamic_tag>
    """
  end
end
