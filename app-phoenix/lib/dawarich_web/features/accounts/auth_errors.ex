defmodule DawarichWeb.AuthErrors do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :messages, :list, required: true
  attr :heading, :string, default: nil

  def summary(assigns) do
    assigns =
      assign(assigns, heading: assigns.heading || heading(assigns.locale, assigns.messages))

    ~H"""
    <div
      id="error_explanation"
      class="alert alert-error mb-4 min-w-0 [overflow-wrap:anywhere]"
      role="alert"
      tabindex="-1"
      data-auth-error-summary
    >
      <DawarichWeb.Icon.icon name="circle-x" class="size-6" />
      <div class="font-bold mb-4 flex items-center gap-2">
        <div>
          <h3 class="font-bold">{@heading}</h3>
          <ul class="text-sm mt-1">
            <li :for={message <- @messages}>{message}</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :error, :boolean, default: false
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <%= if @error do %>
      <div class="field_with_errors">{render_slot(@inner_block)}</div>
    <% else %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  defp heading(locale, messages) do
    resource =
      case Dawarich.I18n.t(locale, "activerecord.models.user", %{"count" => 1}) do
        {:ok, value} when is_binary(value) -> String.downcase(value)
        _ -> "user"
      end

    t(locale, "errors.messages.not_saved", %{count: length(messages), resource: resource})
  end
end
