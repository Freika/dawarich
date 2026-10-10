defmodule DawarichWeb.AuthPageController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn
  alias DawarichWeb.Layouts

  def document(conn, body, status, opts) do
    user = if Keyword.fetch!(opts, :chrome) == :authenticated, do: conn.assigns.current_user

    assigns = %{
      __changed__: nil,
      current_user: user,
      locale: conn.assigns.locale,
      self_hosted: conn.assigns.self_hosted,
      now: conn.assigns.now,
      request_path: conn.assigns.request_path,
      query_params: conn.assigns.query_params,
      base_url: conn.assigns[:base_url] || "",
      suggested_locale: conn.assigns[:suggested_locale],
      flash: Keyword.get(opts, :flash, %{}),
      flash_messages: conn.assigns.flash_messages,
      rails_csrf_token: Keyword.fetch!(opts, :csrf_token),
      page_title: Keyword.get(opts, :title),
      navbar: Keyword.get(opts, :navbar, conn.assigns[:navbar]),
      inner_content: body
    }

    app = Layouts.auth_app(assigns)
    html = Layouts.auth_root(%{assigns | inner_content: app}) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end
end
