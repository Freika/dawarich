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
    opts =
      Keyword.put_new(opts, :exception, Enum.take(conn.path_info, 3) == ["api", "v1", "families"])

    conn = assign(conn, :api_params, conn.assigns[:api_params] || %{})
    format = DawarichWeb.Api.RequestFormat.decide(conn)

    {type, body} =
      if match?({:ok, :json, _}, format) do
        {"application/json",
         Dawarich.RubyJson.encode_exact!(
           Jason.OrderedObject.new([{"status", status}, {"error", @reasons[status]}])
         )}
      else
        page = Dawarich.RailsRoot.join("public/#{status}.html")

        if File.exists?(page),
          do: {"text/html", File.read!(page)},
          else: {"text/plain", @reasons[status]}
      end

    conn =
      if opts[:exception] do
        %{conn | resp_headers: []}
        |> put_resp_header("x-request-id", conn.assigns[:api_request_id] || Ecto.UUID.generate())
        |> put_resp_header("x-runtime", "0.000000")
      else
        conn
      end

    conn = if conn.method == "HEAD", do: Plug.Head.call(conn, []), else: conn

    conn =
      if opts[:transport] || opts[:exception],
        do: delete_resp_header(conn, "cache-control"),
        else: DawarichWeb.RailsHeaders.call(conn, [])

    conn
    |> put_resp_content_type(
      type,
      if(type == "text/html" or opts[:exception] == true, do: "UTF-8", else: "utf-8")
    )
    |> send_resp(status, body)
    |> halt()
  end
end
