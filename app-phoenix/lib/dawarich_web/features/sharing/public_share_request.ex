defmodule DawarichWeb.PublicShareRequest do
  @moduledoc false
  import Plug.Conn

  def owned?(%{path_info: ["s", _]} = conn), do: conn.method in ["GET", "HEAD"]

  def owned?(%{path_info: ["s", _, "unlock"]} = conn),
    do: (conn.private[:dawarich_original_method] || conn.method) == "POST"

  def owned?(_), do: false
  def init(opts), do: opts

  def call(conn, _) do
    conn = conn |> put_private(:dawarich_native_api, true) |> DawarichWeb.Api.Transport.parse()
    if conn.halted, do: conn, else: validate(conn)
  end

  defp validate(%{method: "POST"} = conn) do
    params = conn.assigns.api_params
    type = DawarichWeb.Api.Transport.media_type(conn)

    invalid =
      type not in ["", "application/x-www-form-urlencoded"] or
        get_req_header(conn, "x-http-method-override") != [] or
        Enum.any?(~w(_method client), &Map.has_key?(params, &1)) or
        Enum.any?(
          ~w(locale format),
          &(Map.has_key?(params, &1) and not Map.has_key?(conn.assigns.api_query, &1))
        ) or
        not (is_nil(params["phrase"]) or is_binary(params["phrase"]))

    if invalid, do: DawarichWeb.RailsErrors.respond(conn, 422), else: conn
  end

  defp validate(conn) do
    format = conn.assigns.api_params["format"]
    body = conn.private[:dawarich_raw_body] || ""
    accept = Enum.join(get_req_header(conn, "accept"), ",")

    cond do
      body != "" or Map.has_key?(conn.assigns.api_params, "client") or
          get_req_header(conn, "x-dawarich-client") != [] ->
        DawarichWeb.RailsErrors.respond(conn, 422)

      format not in [nil, "html"] or
          (accept != "" and
             not Enum.any?(~w(text/html application/xhtml+xml */*), &String.contains?(accept, &1))) ->
        conn |> put_resp_content_type("text/plain") |> send_resp(406, "") |> halt()

      true ->
        conn
    end
  end
end
