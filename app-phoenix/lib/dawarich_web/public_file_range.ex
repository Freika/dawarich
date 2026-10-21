defmodule DawarichWeb.PublicFileRange do
  @moduledoc false
  import Plug.Conn

  def serve(conn, path, size, mtime, headers) do
    conn = %{conn | resp_headers: headers}
    conn = put_resp_header(conn, "accept-ranges", "bytes")

    case parse(get_req_header(conn, "range"), size) do
      {:ok, first, last} ->
        modified = Calendar.strftime(DateTime.from_unix!(mtime), "%a, %d %b %Y %H:%M:%S GMT")

        conn
        |> put_resp_header("last-modified", modified)
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> put_resp_header("content-length", to_string(last - first + 1))
        |> send_file(206, path, first, last - first + 1)
        |> halt()

      :error ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
        |> halt()
    end
  end

  defp parse([header], size) when byte_size(header) < 128 and size > 0 do
    with [_, first, last] <- Regex.run(~r/\Abytes=(\d+)-(\d*)\z/, header),
         first <- String.to_integer(first),
         last <- if(last == "", do: size - 1, else: min(String.to_integer(last), size - 1)),
         true <- first < size and first <= last do
      {:ok, first, last}
    else
      _ -> :error
    end
  end

  defp parse(_, _), do: :error
end
