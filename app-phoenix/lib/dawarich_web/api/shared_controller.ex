defmodule DawarichWeb.Api.SharedController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{Accounts, RailsCookies, RailsSecret, SharedLinks, UserTimeZone}
  alias DawarichWeb.Api.{Body, Respond}
  alias DawarichWeb.SharedLinkCookie

  def init(action), do: action

  def call(conn, action) do
    conn = frame(conn)

    if supported?(conn) do
      now = conn.assigns[:api_now] || DateTime.utc_now()
      id = conn.path_params["id"]

      if SharedLinks.api_uuid?(id) && not SharedLinks.api_owner_available?(id) do
        Body.replay(conn, "shared owner unavailable")
      else
        link = if SharedLinks.api_uuid?(id), do: SharedLinks.active(id, now)

        cond do
          is_nil(link) -> error(conn, 404, "not_found")
          not SharedLinkCookie.unlocked?(conn, link, now) -> error(conn, 401, "unauthorized")
          true -> dispatch(conn, action, link)
        end
      end
    else
      Body.replay(conn, "unsupported shared API request")
    end
  end

  defp frame(conn) do
    request_id = conn |> get_req_header("x-request-id") |> Enum.join(", ")

    request_id =
      if String.trim(request_id) == "",
        do: Ecto.UUID.generate(),
        else: request_id |> String.replace(~r/[^\w\-@]/, "") |> String.slice(0, 255)

    conn
    |> assign(:api_started, System.monotonic_time())
    |> assign(:api_headers, [])
    |> assign(:api_request_id, request_id)
    |> assign(
      :api_vary,
      get_req_header(conn, "accept") != [] and not Map.has_key?(conn.assigns.api_params, "format")
    )
    |> assign(:api_if_none_match, conn |> get_req_header("if-none-match") |> Enum.join(", "))
  end

  defp supported?(conn) do
    client =
      List.first(get_req_header(conn, "x-dawarich-client")) || conn.assigns.api_params["client"]

    not Map.has_key?(fetch_cookies(conn).req_cookies, "remember_user_token") and
      client not in ["ios", "android"] and
      get_req_header(conn, "x-requested-with") == [] and
      conn.assigns.api_params["format"] in [nil, "json"] and
      not Enum.any?(conn.req_headers, fn {name, _} -> String.contains?(name, "_") end) and
      length(get_req_header(conn, "cookie")) <= 1
  end

  defp dispatch(conn, :route, link),
    do: result(conn, Dawarich.SharedApi.Points.route(link), cache_control: cache(link))

  defp dispatch(conn, :trip, link),
    do: result(conn, Dawarich.SharedApi.Trip.show(link, zone(conn)), [])

  defp dispatch(conn, :points, %{type: type} = link) when type != "live",
    do: result(conn, Dawarich.SharedApi.Points.index(link), cache_control: cache(link))

  defp dispatch(conn, :points, link),
    do:
      result(
        conn,
        Dawarich.SharedApi.Points.live(link, conn.assigns[:api_now] || DateTime.utc_now()),
        []
      )

  defp dispatch(conn, action, link) when action in [:photos, :thumbnail],
    do: result(conn, Dawarich.SharedApi.Photos.response(link, action), [])

  defp dispatch(conn, _action, _link), do: Body.replay(conn, "shared API action pending")

  defp result(conn, {:ok, term}, opts), do: Respond.json(conn, 200, term, opts)
  defp result(conn, {:error, status, message}, _opts), do: error(conn, status, message)
  defp result(conn, {:replay, reason}, _opts), do: Body.replay(conn, reason)
  defp result(conn, {:head, status}, _opts), do: Respond.head(conn, status, "application/json")

  defp cache(%{magic_phrase: phrase}) do
    if Dawarich.ReleaseMigrations.Effects.Support.Ruby.blank?(phrase),
      do: "max-age=30, public",
      else: "max-age=0, private, must-revalidate"
  end

  defp zone(conn) do
    now = conn.assigns[:api_now] || DateTime.utc_now()
    cookies = fetch_cookies(conn).req_cookies

    with value when is_binary(value) <- cookies["_dawarich_session"],
         {:ok, session} <-
           RailsCookies.decrypt(value, "_dawarich_session", RailsSecret.fetch(), now),
         %Accounts.User{} = user <- Accounts.from_session(session, now) do
      UserTimeZone.name(user.settings)
    else
      _ -> UserTimeZone.name(%{"timezone" => ""})
    end
  end

  defp error(conn, status, message),
    do: Respond.json(conn, status, {:object, [{"error", message}]})
end
