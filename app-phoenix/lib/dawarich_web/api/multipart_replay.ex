defmodule DawarichWeb.Api.MultipartReplay do
  @moduledoc false

  def parse(conn, opts) do
    {adapter, state} = conn.adapter
    conn = %{conn | adapter: {__MODULE__, {adapter, state, []}}}
    conn = conn |> Plug.Parsers.call(opts) |> drain()
    {__MODULE__, {adapter, state, parts}} = conn.adapter

    %{conn | adapter: {adapter, state}}
    |> Plug.Conn.put_private(:dawarich_raw_body, parts |> Enum.reverse() |> IO.iodata_to_binary())
  end

  def read_req_body({adapter, state, parts}, opts) do
    case adapter.read_req_body(state, opts) do
      {result, bytes, state} when result in [:ok, :more] ->
        {result, bytes, {adapter, state, [bytes | parts]}}

      error ->
        error
    end
  end

  defp drain(conn) do
    case Plug.Conn.read_body(conn, DawarichWeb.RailsProxy.read_options()) do
      {:more, _bytes, conn} -> drain(conn)
      {:ok, _bytes, conn} -> conn
      {:error, reason} -> raise Plug.BadRequestError, message: inspect(reason)
    end
  end
end
