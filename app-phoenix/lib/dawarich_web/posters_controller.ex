defmodule DawarichWeb.PostersController do
  @moduledoc false
  use DawarichWeb, :html
  import Plug.Conn
  alias Dawarich.Posters.Persistence

  alias DawarichWeb.{
    Chrome,
    Locale,
    MapGalleryCards,
    PostersGate,
    RailsSession,
    RequestURL,
    Translate
  }

  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, action) do
    params = conn.assigns.api_params
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    conn = Plug.Conn.assign(conn, :locale, locale)

    if PostersGate.supported?(conn, params),
      do: run(conn, action, params),
      else: Body.replay(conn, "poster parameters")
  end

  defp run(conn, :create, params) do
    result =
      case params["poster"] do
        value when is_map(value) and map_size(value) > 0 ->
          Persistence.create(value, conn.assigns.current_user, conn.assigns.locale)

        _ ->
          {:error, :missing}
      end

    case result do
      {:ok, id} ->
        if turbo?(conn) do
          poster = Dawarich.MapGallery.poster(conn.assigns.current_user.id, id)

          streams(
            conn,
            :create,
            poster,
            "notice",
            notice(conn, "poster_generation_started_this_takes_about_a_minute"),
            200
          )
        else
          redirect(
            conn,
            "notice",
            notice(conn, "poster_generation_started_this_takes_about_a_minute"),
            302
          )
        end

      {:error, _} ->
        message = notice(conn, "failed_to_start_poster_generation")

        if turbo?(conn),
          do: streams(conn, :error, nil, "error", message, 422),
          else: redirect(conn, "alert", message, 422)
    end
  end

  defp run(conn, :destroy, _) do
    id = String.to_integer(conn.path_params["id"])

    case Persistence.delete(id, conn.assigns.current_user) do
      {:ok, ^id} ->
        if turbo?(conn),
          do:
            conn
            |> put_resp_content_type("text/vnd.turbo-stream.html")
            |> send_resp(
              200,
              ~s(<turbo-stream action="remove" target="poster_#{id}"></turbo-stream>)
            ),
          else: redirect(conn, "notice", notice(conn, "poster_deleted"), 303)

      {:error, :missing} ->
        conn |> put_resp_content_type("text/html") |> send_resp(404, "")
    end
  end

  defp streams(conn, action, poster, type, message, status) do
    content =
      response(%{
        __changed__: nil,
        action: action,
        poster: poster,
        type: type,
        message: message,
        locale: conn.assigns.locale
      })

    conn
    |> put_resp_content_type("text/vnd.turbo-stream.html")
    |> send_resp(status, Phoenix.HTML.Safe.to_iodata(content))
  end

  def response(assigns) do
    ~H"""
    <turbo-stream :if={@action == :create} action="prepend" target="poster-gallery-list">
      <template><MapGalleryCards.poster_card poster={@poster} locale={@locale} /></template>
    </turbo-stream>
    <turbo-stream action="append" target="flash-messages">
      <template><Chrome.flash_message type={@type} message={@message} locale={@locale} /></template>
    </turbo-stream>
    """
  end

  defp turbo?(conn),
    do:
      Enum.any?(
        get_req_header(conn, "accept"),
        &String.contains?(&1, "text/vnd.turbo-stream.html")
      )

  defp notice(conn, key), do: Translate.t(conn.assigns.locale, "controllers.posters." <> key, %{})

  defp redirect(conn, type, message, status) do
    changes = %{"flash" => %{"discard" => [], "flashes" => %{type => message}}}
    conn = RailsSession.stage(conn, changes)
    conn = if status == 422, do: RailsSession.put(conn, changes), else: conn

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> "/map/v2")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
  end
end
