defmodule DawarichWeb.TagErrors do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :errors, :list, default: []

  def alert(assigns) do
    ~H"""
    <div :if={@errors != []} class="alert alert-error">
      <div>
        <h3 class="font-bold">
          {t(@locale, "tags.form.errors_prohibited_save", %{count: length(@errors)})}
        </h3>
        <ul class="list-disc list-inside">
          <li :for={error <- @errors}>{error["message"]}</li>
        </ul>
      </div>
    </div>
    """
  end

  attr :errors, :list, default: []
  attr :field, :string, required: true
  slot :inner_block, required: true

  def field(assigns) do
    assigns =
      assign(assigns, :invalid, Enum.any?(assigns.errors, &(&1["attribute"] == assigns.field)))

    ~H"""
    <div :if={@invalid} class="field_with_errors">{render_slot(@inner_block)}</div>
    <%= if not @invalid do %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end
end
