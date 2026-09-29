defmodule DawarichWeb.RequestURL do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  def base(conn) do
    ssl = DawarichWeb.RackScheme.ssl?(conn)
    authority = authority(conn)
    standard = if ssl, do: 443, else: 80

    port =
      case Regex.run(~r/:(\d+)\z/, authority) do
        [_, digits] -> String.to_integer(digits)
        nil -> standard
      end

    host = String.replace(authority, ~r/:\d+\z/, "")
    scheme = if ssl, do: "https://", else: "http://"
    scheme <> host <> if(port == standard, do: "", else: ":#{port}")
  end

  defp authority(conn) do
    case conn |> get_req_header("x-forwarded-host") |> Enum.join(", ") do
      "" -> List.first(get_req_header(conn, "host")) || "#{conn.host}:#{conn.port}"
      forwarded -> forwarded |> String.split(~r/,\s?/, trim: true) |> List.last()
    end
  end
end
