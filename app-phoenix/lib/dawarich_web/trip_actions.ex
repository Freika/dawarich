defmodule DawarichWeb.TripActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Jobs, Trips.WebWrite, Trips.WebDelete, Trips.WebForm}
  alias DawarichWeb.{Locale, RailsCsrf, RailsSession, RequestURL, Translate, TripForm}

  def init(action), do: action

  def call(conn, :export), do: DawarichWeb.TripExportAction.call(conn)

  def call(conn, :member),
    do: call(conn, if(conn.assigns.a8_action == :trip_destroy, do: :destroy, else: :update))

  def call(conn, :recalculate) do
    user = conn.assigns.current_user

    ctx = %{
      now: conn.assigns[:now] || DateTime.utc_now(),
      locale: Locale.resolve(nil, user, conn.assigns.rails_session)
    }

    id = String.to_integer(conn.path_params["id"])

    case Dawarich.Trips.WebRecalculate.run(Jobs.repo(), user, id, ctx) do
      {:ok, result} ->
        notice =
          Translate.t(
            ctx.locale,
            "controllers.trips." <>
              if(result == :queued,
                do: "recalculating_the_page_will_update_automatically_when_it_s_ready",
                else: "already_recalculating_this_page_will_update_when_it_s_done"
              ),
            %{}
          )

        if conn.assigns.a8_format == :turbo_stream do
          html = DawarichWeb.TripRecalculateStream.render(id, result, notice, ctx.locale)

          conn
          |> put_resp_header("vary", "Accept")
          |> put_resp_content_type("text/vnd.turbo-stream.html")
          |> send_resp(200, html)
          |> halt()
        else
          redirect(conn, 302, "/trips/#{id}", notice)
        end

      {:replay, reason} ->
        DawarichWeb.TripRequest.replay(conn, reason)

      {:error, :not_found} ->
        not_found(conn)

      {:error, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end

  def call(conn, action) do
    user = conn.assigns.current_user

    ctx = %{
      now: conn.assigns[:now] || DateTime.utc_now(),
      locale: Locale.resolve(nil, user, conn.assigns.rails_session)
    }

    id = conn.path_params["id"] && String.to_integer(conn.path_params["id"])

    if action == :create and not WebForm.active?(user, ctx.now) do
      DawarichWeb.TripRequest.replay(conn, "inactive trip create")
    else
      case change(conn, action, user, id, ctx) do
        {:ok, result} ->
          path = if action == :destroy, do: "/trips", else: "/trips/#{result.id}"

          key =
            case action do
              :create -> "trip_was_successfully_created_data_is_being_calculated_in_the"
              :update -> "trip_was_successfully_updated"
              :destroy -> "trip_was_successfully_destroyed"
            end

          redirect(
            conn,
            if(action == :create, do: 302, else: 303),
            path,
            Translate.t(ctx.locale, "controllers.trips.#{key}", %{})
          )

        {:invalid, errors, values} ->
          if action == :create and conn.assigns.a8_format == :turbo_stream do
            conn |> send_resp(500, "") |> halt()
          else
            case WebForm.load(Jobs.repo(), user, id, ctx) do
              {:ok, form} -> invalid(conn, WebForm.invalid(form, errors, values), ctx.locale)
              _ -> DawarichWeb.TripRequest.replay(conn, "trip validation form")
            end
          end

        {:replay, reason} ->
          DawarichWeb.TripRequest.replay(conn, reason)

        {:error, :not_found} ->
          not_found(conn)

        {:error, _} ->
          conn |> send_resp(500, "") |> halt()
      end
    end
  end

  defp change(_conn, :destroy, user, id, ctx), do: WebDelete.run(Jobs.repo(), user, id, ctx)

  defp change(conn, action, user, id, ctx),
    do: WebWrite.run(Jobs.repo(), action, user, id, conn.assigns.api_params["trip"], ctx)

  defp invalid(conn, form, locale) do
    conn = conn |> fetch_query_params() |> DawarichWeb.LayoutAssigns.call([])

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        navbar:
          Dawarich.Navbar.load(conn.assigns.current_user,
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          ),
        flash: %{},
        page_title:
          Translate.t(
            locale,
            if(form.id, do: "trips.edit.editing_trip", else: "trips.new.new_trip"),
            %{}
          ),
        rails_js: true,
        rails_trix: true,
        rails_charts: false
      })

    content =
      TripForm.page(%{
        __changed__: nil,
        form: form,
        locale: locale,
        csrf: RailsCsrf.masked_token(conn.assigns.rails_session),
        base_url: RequestURL.base(conn)
      })

    app = DawarichWeb.Layouts.app(Map.put(assigns, :inner_content, content))

    html =
      DawarichWeb.Layouts.root(Map.put(assigns, :inner_content, app))
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("vary", "Accept")
    |> put_resp_content_type("text/html")
    |> send_resp(422, html)
    |> halt()
  end

  def redirect(conn, status, path, notice) do
    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end

  def not_found(conn) do
    html = DawarichWeb.ErrorHTML.render("404.html", %{}) |> Phoenix.HTML.Safe.to_iodata()
    conn |> put_resp_content_type("text/html") |> send_resp(404, html) |> halt()
  end
end
