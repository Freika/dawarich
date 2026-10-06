defmodule DawarichWeb.AreaActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  use DawarichWeb, :html
  alias Dawarich.Areas.WebWrite
  alias DawarichWeb.{Chrome, Locale, Translate}

  def init(action), do: action

  def call(conn, _) do
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    ctx = %{now: Map.get(conn.assigns, :now, DateTime.utc_now()), locale: locale}
    attrs = conn.assigns.api_params

    outcome =
      case conn.assigns.map_write_action do
        :area_create ->
          WebWrite.create(Dawarich.Repo, user, attrs, ctx)

        :area_update ->
          WebWrite.update(
            Dawarich.Repo,
            user,
            conn.path_info |> List.last() |> String.to_integer(),
            attrs,
            ctx
          )
      end

    case {outcome, conn.assigns.map_write_format} do
      {:rails, _} ->
        DawarichWeb.Api.Body.replay(conn, "area relabel owner")

      {:not_found, _} ->
        conn |> send_resp(404, "") |> halt()

      {_, :unsupported} ->
        conn |> send_resp(406, "") |> halt()

      {{:ok, _}, _} ->
        key = if conn.assigns.map_write_action == :area_create, do: "created", else: "updated"
        flash(conn, "success", Translate.t(locale, "controllers.areas.#{key}", %{}), locale)

      {{:invalid, errors}, _} ->
        flash(conn, "error", Enum.join(errors, ", "), locale)
    end
  end

  def flash(conn, type, message, locale) do
    content =
      Chrome.flash_message(%{__changed__: nil, type: type, message: message, locale: locale})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    body = Dawarich.Cable.turbo_tag("append", "flash-messages", content)

    conn
    |> put_resp_content_type("text/vnd.turbo-stream.html")
    |> put_resp_header("vary", "Accept")
    |> send_resp(200, body)
    |> halt()
  end
end
