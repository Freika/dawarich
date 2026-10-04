defmodule DawarichWeb.AchievementActions.Response do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RailsHeaders, RequestURL}

  def sharing(conn, result, context) do
    conn = RailsHeaders.call(conn, [])

    if json?(conn) do
      body =
        Jason.encode!(%{
          enabled: result.enabled,
          uuid: result.uuid,
          url: public_url(conn, result)
        })

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
      |> send_resp(200, body)
      |> halt()
    else
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("location", redirect(conn, context.key))
      |> send_resp(302, "")
      |> halt()
    end
  end

  def terminal(%{state: state} = conn) when state in [:sent, :chunked], do: halt(conn)

  def terminal(conn),
    do: conn |> put_resp_header("cache-control", "no-cache") |> send_resp(500, "") |> halt()

  def json?(conn), do: get_req_header(conn, "accept") == ["application/json"]

  def supported?(conn),
    do:
      json?(conn) or
        (DawarichWeb.Strangler.page_request?(conn) and
           not Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "turbo-stream")))

  defp public_url(conn, %{enabled: true, uuid: uuid}),
    do: RequestURL.base(conn) <> "/shared/achievements/" <> uuid

  defp public_url(_, _), do: nil

  defp redirect(conn, key) do
    base = RequestURL.base(conn)
    fallback = base <> "/achievements/" <> key

    case get_req_header(conn, "referer") do
      [value] ->
        uri = URI.parse(value)
        origin = URI.parse(base)

        if uri.host == origin.host and uri.scheme in [nil, origin.scheme] and
             uri.port in [nil, origin.port] and not String.contains?(value, ["\r", "\n"]),
           do: value,
           else: fallback

      _ ->
        fallback
    end
  end
end
