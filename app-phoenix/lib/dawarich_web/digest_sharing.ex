defmodule DawarichWeb.DigestSharing do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, Digests.Sharing}
  alias DawarichWeb.{LayoutAssigns, RequestURL, StatsActions, Translate}

  def init(action), do: action

  def call(conn, :update),
    do:
      update(conn, "digests", fn user, attrs, ctx ->
        Sharing.update(Repo, user, conn.path_params["year"], attrs, ctx)
      end)

  def update(conn, scope, fun) do
    user = conn.assigns.current_user
    now = conn.assigns[:now] || DateTime.utc_now()

    ctx = %{
      now: now,
      locale: conn.assigns.locale,
      base_url: RequestURL.base(conn),
      self_hosted: LayoutAssigns.self_hosted?()
    }

    cond do
      not StatsActions.active?(user, now) ->
        StatsActions.inactive(conn, ctx.locale)

      scope == "stats" and not Dawarich.Entitlements.full_access?(user, ctx.self_hosted, now) ->
        message =
          Translate.t(ctx.locale, "controllers.application.this_feature_requires_a_pro_plan", %{})

        if conn.assigns.sharing_format == :json,
          do: json(conn, 403, %{"error" => message}),
          else:
            StatsActions.redirect(conn, %{status: 303, path: "/", flash: :alert, message: message})

      true ->
        case fun.(user, conn.assigns.api_params, ctx) do
          {:ok, result} -> respond(conn, result.body, ctx, scope)
          :not_found -> conn |> send_resp(404, "") |> halt()
          {:error, _} -> failure(conn, ctx, scope)
        end
    end
  rescue
    _error -> failure(conn, %{locale: conn.assigns.locale}, scope)
  end

  defp respond(conn, body, ctx, scope) do
    case conn.assigns.sharing_format do
      :json ->
        json(conn, 200, body)

      :turbo_stream ->
        link =
          DawarichWeb.SharingParts.sharing_link(%{
            __changed__: nil,
            locale: ctx.locale,
            url: body["sharing_url"]
          })
          |> Phoenix.HTML.Safe.to_iodata()
          |> IO.iodata_to_binary()

        message = Translate.t(ctx.locale, "controllers.shared.#{scope}.auto_saved", %{})

        stream(
          conn,
          200,
          "<turbo-stream action=\"replace\" target=\"sharing-link-display\"><template>#{link}</template></turbo-stream>" <>
            flash(message, "success", ctx.locale)
        )

      :unsupported ->
        conn |> send_resp(406, "") |> halt()
    end
  end

  defp failure(conn, ctx, scope) do
    message =
      Translate.t(
        ctx.locale,
        "controllers.shared.#{scope}.failed_to_update_sharing_settings",
        %{}
      )

    if conn.assigns.sharing_format == :json,
      do: json(conn, 422, %{"success" => false, "message" => message}),
      else: stream(conn, 200, flash(message, "error", ctx.locale))
  end

  defp flash(message, type, locale) do
    html =
      DawarichWeb.Chrome.flash_message(%{
        __changed__: nil,
        message: message,
        type: type,
        locale: locale
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    "<turbo-stream action=\"append\" target=\"flash-messages\"><template>#{html}</template></turbo-stream>"
  end

  defp json(conn, status, body),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "no-cache")
      |> send_resp(status, Jason.encode!(body))
      |> halt()

  defp stream(conn, status, body),
    do:
      conn
      |> put_resp_content_type("text/vnd.turbo-stream.html")
      |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
      |> send_resp(status, body)
      |> halt()
end
