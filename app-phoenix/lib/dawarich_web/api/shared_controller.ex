defmodule DawarichWeb.Api.SharedController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.SharedLinks
  alias DawarichWeb.Api.{Body, Respond}
  alias DawarichWeb.SharedLinkCookie

  def init(action), do: action

  def call(conn, action) do
    conn = frame(conn)

    if supported?(conn) do
      now = DateTime.utc_now()
      id = conn.path_params["id"]
      link = if SharedLinks.canonical?(id), do: SharedLinks.active(id, now)

      cond do
        is_nil(link) -> error(conn, 404, "not_found")
        not SharedLinkCookie.unlocked?(conn, link, now) -> error(conn, 401, "unauthorized")
        true -> dispatch(conn, action, link)
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

    client not in ["ios", "android"] and
      get_req_header(conn, "x-requested-with") == [] and
      conn.assigns.api_params["format"] in [nil, "json"] and
      not Enum.any?(conn.req_headers, fn {name, _} -> String.contains?(name, "_") end) and
      length(get_req_header(conn, "cookie")) <= 1
  end

  defp dispatch(conn, :route, %{type: type} = link) when type != "live",
    do: Respond.json(conn, 200, [], cache_control: cache(link))

  defp dispatch(conn, _action, _link), do: Body.replay(conn, "shared API action pending")

  defp cache(%{magic_phrase: phrase}) do
    if Dawarich.ReleaseMigrations.Effects.Support.Ruby.blank?(phrase),
      do: "max-age=30, public",
      else: "max-age=0, private, must-revalidate"
  end

  defp error(conn, status, message),
    do: Respond.json(conn, status, {:object, [{"error", message}]})
end
