defmodule DawarichWeb.Api.RequestBody do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  @read [length: 1_048_576, read_length: 1_048_576, read_timeout: 60_000]

  def read_options, do: @read

  def chunked?(conn), do: get_req_header(conn, "transfer-encoding") != []

  def body?(conn),
    do: chunked?(conn) or Enum.any?(get_req_header(conn, "content-length"), &(&1 != "0"))
end
