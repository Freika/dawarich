defmodule DawarichWeb.ShareManagementForm do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.ShareManagement.{Mutations, Params}

  alias DawarichWeb.{
    Locale,
    RailsCsrf,
    RailsSession,
    RequestURL,
    ShareManagementDocument,
    ShareManagementGate,
    ShareManagementPage,
    ShareManagementStreams,
    Translate
  }

  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, {type, action}) do
    user = conn.assigns.current_user
    params = conn.assigns.api_params
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    now = Map.get(conn.assigns, :now, DateTime.utc_now())
    id = if type == "shared", do: conn.path_params["id"], else: trip_id(conn.path_params)

    if supported?(conn, params, action) and ShareManagementGate.readable_hub?(user, params, now) do
      conn = conn |> assign(:locale, locale) |> assign(:now, now)
      result = Mutations.run(user, type, id, action, params, locale, now: now)
      respond(conn, {type, action}, params, result)
    else
      Body.replay(conn, "share management parameters")
    end
  end

  def respond(conn, {type, action}, params, {:ok, %{committed?: true} = result}) do
    if present?(params["hub"]) do
      ShareManagementStreams.respond(conn, params, tab(type), [], 200)
    else
      path = if type == "shared", do: "/map/v2", else: base(type, result.trip) <> "/new"
      flash = if type == "shared", do: %{}, else: %{"notice" => notice(conn, action)}
      redirect(conn, path, flash)
    end
  end

  def respond(conn, {type, _}, params, {:invalid, result}) do
    if present?(params["hub"]) do
      ShareManagementStreams.respond(
        conn,
        params,
        tab(type),
        Enum.map(result.errors, &elem(&1, 1)),
        422
      )
    else
      conn = presentation(conn)

      content =
        ShareManagementDocument.frame(%{
          __changed__: nil,
          ctx: ShareManagementPage.context(conn),
          page: %{share: nil, trip: result.trip},
          type: type
        })

      ShareManagementPage.respond(conn, content, 422)
    end
  end

  def respond(conn, _, _, {:missing, path}),
    do:
      redirect(conn, path, %{
        "alert" =>
          Translate.t(
            conn.assigns.locale,
            "controllers.concerns.share_links.managable.no_active_share_link",
            %{}
          )
      })

  def respond(conn, {type, _}, _, {:error, 404}) do
    body =
      if type == "shared",
        do: "",
        else: Translate.t(conn.assigns.locale, "controllers.trips.share_links.not_found", %{})

    conn
    |> put_resp_content_type(if(type == "shared", do: "text/html", else: "text/plain"))
    |> send_resp(404, body)
  end

  def respond(conn, _, _, :rails), do: Body.replay(conn, "share management shape")

  def presentation(conn) do
    conn
    |> assign(:base_url, RequestURL.base(conn))
    |> assign(:self_hosted, true)
    |> assign(:rails_csrf_token, RailsCsrf.masked_token(conn.assigns.rails_session))
    |> assign(:request_path, conn.request_path)
    |> assign(:suggested_locale, nil)
    |> assign(:flash_messages, [])
  end

  defp supported?(conn, params, action) do
    allowed = ~w(authenticity_token commit hub start_date end_date)
    allowed = if action == :create, do: ["shared_link" | allowed], else: allowed
    accept = get_req_header(conn, "accept") |> Enum.join(",")

    not Map.has_key?(params, "format") and
      (accept == "" or DawarichWeb.Strangler.browser_like?(accept) or
         Enum.all?(String.split(accept, ","), fn value ->
           (value |> String.split(";") |> hd() |> String.trim()) in ~w(text/html */* application/xhtml+xml text/vnd.turbo-stream.html)
         end)) and
      Enum.all?(params, fn {key, value} ->
        key in allowed and
          (key == "shared_link" or is_binary(value))
      end) and
      Enum.all?(~w(start_date end_date), &Params.date_shape?(params[&1]))
  end

  defp present?(nil), do: false
  defp present?(text), do: String.trim(text) != ""
  defp trip_id(%{"trip_id" => id}), do: String.to_integer(id)
  defp trip_id(_), do: nil
  defp tab("live"), do: "live"
  defp tab("shared"), do: "shared"
  defp tab("trip"), do: nil
  defp base("live", _), do: "/share_links/live"
  defp base("trip", trip), do: "/trips/#{trip.id}/share_link"

  defp notice(conn, action) do
    key =
      %{
        create: "created",
        destroy: "deleted",
        revoke: "revoked",
        regenerate: "url_regenerated",
        regenerate_phrase: "magic_phrase_regenerated"
      }[action]

    Translate.t(conn.assigns.locale, "controllers.concerns.share_links.managable." <> key, %{})
  end

  defp redirect(conn, path, flash) do
    conn =
      if flash == %{},
        do: conn,
        else:
          RailsSession.stage(
            conn,
            %{"flash" => %{"discard" => [], "flashes" => flash}}
          )

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
