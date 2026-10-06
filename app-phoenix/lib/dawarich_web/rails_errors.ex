defmodule DawarichWeb.RailsErrors do
  @moduledoc false
  import Plug.Conn

  @reasons %{
    400 => "Bad Request",
    404 => "Not Found",
    413 => "Content Too Large",
    422 => "Unprocessable Content",
    500 => "Internal Server Error"
  }

  def respond(conn, status, opts \\ [])

  def respond(%{state: state} = conn, _status, _opts) when state in [:sent, :chunked],
    do: halt(conn)

  def respond(conn, status, opts) do
    conn = assign(conn, :api_params, conn.assigns[:api_params] || %{})
    format = DawarichWeb.Api.RequestFormat.decide(conn)

    {type, body} =
      if match?({:ok, :json, _}, format) do
        {"application/json",
         Dawarich.RubyJson.encode_exact!(
           Jason.OrderedObject.new([{"status", status}, {"error", @reasons[status]}])
         )}
      else
        {"text/html", File.read!(Dawarich.RailsRoot.join("public/#{status}.html"))}
      end

    conn = if conn.method == "HEAD", do: Plug.Head.call(conn, []), else: conn

    conn =
      if opts[:transport],
        do: delete_resp_header(conn, "cache-control"),
        else: DawarichWeb.RailsHeaders.call(conn, [])

    conn
    |> put_resp_content_type(type, if(type == "text/html", do: "UTF-8", else: "utf-8"))
    |> send_resp(status, body)
    |> halt()
  end
end
