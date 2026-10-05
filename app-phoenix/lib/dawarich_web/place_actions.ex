defmodule DawarichWeb.PlaceActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, PlaceDrawer, Places.WebWrite, Places.WebDelete}
  alias DawarichWeb.{PlaceStreams, Locale, Translate, RailsSession, RailsCsrf, RequestURL}
  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, :member),
    do: call(conn, if(conn.assigns.a8_action == :place_destroy, do: :destroy, else: :update))

  def call(conn, action) do
    user = conn.assigns.current_user
    id = conn.path_params["id"] && String.to_integer(conn.path_params["id"])
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    ctx = %{now: conn.assigns[:now] || DateTime.utc_now(), locale: locale}

    with :ok <- preflight(conn, action, user, id) do
      result =
        if action == :destroy do
          WebDelete.run(Repo, user, id, ctx)
        else
          WebWrite.run(Repo, action, user, id, conn.assigns.api_params["place"], ctx)
        end

      case result do
        {:ok, saved} ->
          success(conn, action, user, saved, locale)

        {:invalid, errors} ->
          message = Enum.join(errors, ", ")

          if conn.assigns.a8_format == :turbo_stream do
            respond(conn, PlaceStreams.render(:error, %{message: message, locale: locale}))
          else
            redirect(conn, "/map/v2?place_id=#{id}", "alert", message)
          end

        {:replay, reason} ->
          Body.replay(conn, reason)

        {:error, :not_found} ->
          not_found(conn)

        {:error, _} ->
          conn |> send_resp(500, "") |> halt()
      end
    else
      {:replay, reason} -> Body.replay(conn, reason)
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp preflight(conn, :create, _user, _id) when conn.assigns.a8_format != :turbo_stream,
    do: {:replay, "place create HTML negotiation"}

  defp preflight(_conn, action, user, id) do
    if Dawarich.PlaceList.settings?(user.settings) and
         Dawarich.TripSettings.zone?(user.settings, Dawarich.UserTimeZone.name(user.settings)) do
      if action == :update do
        case PlaceDrawer.load(user, id) do
          {:ok, _} ->
            :ok

          :rails ->
            if Repo.query!("SELECT id FROM places WHERE id=$1 AND user_id=$2", [id, user.id],
                 log: false
               ).rows == [],
               do: {:error, :not_found},
               else: {:replay, "place drawer state"}
        end
      else
        :ok
      end
    else
      {:replay, "place settings"}
    end
  end

  defp success(conn, action, user, saved, locale) do
    id = if action == :destroy, do: saved, else: saved.id
    framed = get_req_header(conn, "turbo-frame") == ["place-drawer"]

    message =
      Translate.t(
        locale,
        "controllers.places." <>
          case action do
            :create -> "created"
            :update -> "updated"
            :destroy -> "place_was_successfully_destroyed"
          end,
        %{}
      )

    if conn.assigns.a8_format == :turbo_stream or (action == :destroy and framed) do
      drawer =
        if action == :update do
          {:ok, drawer} = PlaceDrawer.load(user, id)
          drawer
        end

      responds = %{
        user: user,
        id: id,
        drawer: drawer,
        framed: framed,
        locale: locale,
        message: message,
        csrf: RailsCsrf.masked_token(conn.assigns.rails_session),
        repo: Repo
      }

      if action == :destroy and not framed do
        redirect(conn, list_path(conn), "notice", message)
      else
        respond(conn, PlaceStreams.render(action, responds))
      end
    else
      path = if action == :destroy, do: list_path(conn), else: "/map/v2?place_id=#{id}"
      redirect(conn, path, if(action == :destroy, do: "notice", else: nil), message)
    end
  end

  defp not_found(conn) do
    html = DawarichWeb.ErrorHTML.render("404.html", %{}) |> Phoenix.HTML.Safe.to_iodata()
    conn |> put_resp_content_type("text/html", "UTF-8") |> send_resp(404, html) |> halt()
  end

  defp list_path(conn),
    do:
      "/places" <>
        if(conn.assigns.api_query["page"],
          do: "?" <> URI.encode_query(%{"page" => conn.assigns.api_query["page"]}),
          else: ""
        )

  defp redirect(conn, path, key, message) do
    conn =
      if key,
        do:
          RailsSession.stage(conn, %{
            "flash" => %{"discard" => [], "flashes" => %{key => message}}
          }),
        else: conn

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(303, "")
    |> halt()
  end

  defp respond(conn, html),
    do:
      conn
      |> put_resp_header("vary", "Accept")
      |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
      |> put_resp_content_type("text/vnd.turbo-stream.html")
      |> send_resp(200, html)
      |> halt()
end
