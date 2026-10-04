defmodule DawarichWeb.VisitActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Jobs
  alias Dawarich.Visits.{WebUpdate, WebDelete, WebBulk, WebMerge}

  alias DawarichWeb.{
    Locale,
    RailsCsrf,
    RailsSession,
    RequestURL,
    VisitStreams,
    LayoutAssigns,
    Translate
  }

  alias DawarichWeb.Api.Body

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :member) do
    action = if conn.assigns.a8_action == :visit_destroy, do: :destroy, else: :update
    call(conn, action)
  end

  def call(conn, action) do
    user = conn.assigns.current_user

    ctx = %{
      user: user,
      repo: Jobs.repo(),
      now: conn.assigns[:now] || DateTime.utc_now(),
      self_hosted: LayoutAssigns.self_hosted?(),
      locale: Locale.resolve(nil, user, conn.assigns.rails_session),
      csrf: RailsCsrf.masked_token(conn.assigns.rails_session)
    }

    params = conn.assigns.api_params

    with {:ok, back} <- back(conn, action) do
      case change(action, conn.path_params["id"], params, ctx) do
        {:ok, result} ->
          if conn.assigns.a8_format == :turbo_stream do
            stream(conn, VisitStreams.render(action, result, ctx))
          else
            location = location(action, params, back)
            status = if action in [:destroy, :bulk_destroy], do: 303, else: 302

            redirect(
              conn,
              status,
              location,
              "notice",
              VisitStreams.notice(action, result, ctx.locale)
            )
          end

        {:error, :failed_to_update_visits} ->
          if conn.assigns.a8_format == :turbo_stream do
            stream(conn, VisitStreams.error(ctx.locale, "failed_to_update_visits"))
          else
            redirect(
              conn,
              302,
              location(:bulk_update, params, nil),
              "alert",
              Translate.t(ctx.locale, "controllers.visits.failed_to_update_visits", %{})
            )
          end

        {:error, reason} ->
          Body.replay(conn, "visit error flash #{reason}")

        {:replay, reason} ->
          Body.replay(conn, reason)
      end
    else
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp change(:update, id, params, ctx),
    do: WebUpdate.run(ctx.repo, ctx.user, id, params["visit"], ctx)

  defp change(:destroy, id, params, ctx), do: WebDelete.run(ctx.repo, ctx.user, id, params, ctx)

  defp change(:bulk_update, _id, params, ctx),
    do: WebBulk.run(ctx.repo, :update, ctx.user, params, ctx)

  defp change(:bulk_destroy, _id, params, ctx),
    do: WebBulk.run(ctx.repo, :destroy, ctx.user, params, ctx)

  defp change(:merge, _id, params, ctx),
    do: WebMerge.run(ctx.repo, ctx.user, params["visit_ids"], ctx)

  defp back(_conn, action) when action in [:destroy, :bulk_update], do: {:ok, nil}

  defp back(conn, _action) do
    case get_req_header(conn, "referer") do
      [] ->
        {:ok, nil}

      [value] ->
        uri = URI.parse(value)
        base = URI.parse(RequestURL.base(conn))

        if not String.contains?(value, ["\\", "\r", "\n"]) and is_nil(uri.userinfo) and
             ((uri.host == base.host and uri.scheme == base.scheme and uri.port == base.port) or
                (is_nil(uri.host) and is_nil(uri.scheme) and String.starts_with?(value, "/") and
                   not String.starts_with?(value, "//"))) do
          {:ok, value}
        else
          {:replay, "visit redirect origin"}
        end

      _ ->
        {:replay, "visit referer shape"}
    end
  end

  defp location(:bulk_update, params, _back),
    do: timeline(params["date"] || "today", params["source_status"] || "suggested")

  defp location(:destroy, _params, _back), do: timeline("today", nil)
  defp location(:update, _params, nil), do: timeline("today", "suggested")
  defp location(_action, _params, nil), do: timeline("today", nil)
  defp location(_action, _params, back), do: back

  defp timeline(date, status) do
    pairs = [{"date", if(date == "", do: "today", else: date)}, {"panel", "timeline"}]
    "/map/v2?" <> URI.encode_query(pairs ++ if(status, do: [{"status", status}], else: []))
  end

  defp stream(conn, html),
    do:
      conn
      |> put_resp_content_type("text/vnd.turbo-stream.html")
      |> put_resp_header("vary", "Accept")
      |> send_resp(200, html)
      |> halt()

  defp redirect(conn, status, location, type, message) do
    absolute =
      if String.starts_with?(location, "/"), do: RequestURL.base(conn) <> location, else: location

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{type => message}}})
    |> put_resp_header("location", absolute)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end
end
