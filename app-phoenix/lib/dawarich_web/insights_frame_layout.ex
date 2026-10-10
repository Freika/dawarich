defmodule DawarichWeb.InsightsFrameLayout do
  @moduledoc "turbo-rails 2.0.23 frame layout: html, head with the Rails CSRF metas when present, body."
  use DawarichWeb, :html

  def render(assigns) do
    ~H"""
    <html>
      <head>
        <%= if @rails_csrf_token do %>
          <meta name="csrf-param" content="authenticity_token" />
          <meta name="csrf-token" content={@rails_csrf_token} />
        <% end %>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end
