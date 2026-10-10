defmodule DawarichWeb.Api.MultipartReplay do
  @moduledoc false

  def parse(conn, opts, retained) do
    {adapter, state} = conn.adapter
    conn = %{conn | adapter: {__MODULE__, {adapter, state, {[], retained}}}}
    conn = conn |> Plug.Parsers.call(opts) |> drain()
    {__MODULE__, {adapter, state, kept}} = conn.adapter
    conn = %{conn | adapter: {adapter, state}}

    case kept do
      {parts, _room} ->
        Plug.Conn.put_private(
          conn,
          :dawarich_raw_body,
          parts |> Enum.reverse() |> IO.iodata_to_binary()
        )

      :dropped ->
        conn
    end
  end

  def read_req_body({adapter, state, kept}, opts) do
    case adapter.read_req_body(state, opts) do
      {result, bytes, state} when result in [:ok, :more] ->
        {result, bytes, {adapter, state, keep(kept, bytes)}}

      error ->
        error
    end
  end

  defp keep(:dropped, _bytes), do: :dropped

  defp keep({parts, room}, bytes) when byte_size(bytes) <= room,
    do: {[bytes | parts], room - byte_size(bytes)}

  defp keep(_kept, _bytes), do: :dropped

  defp drain(conn) do
    case Plug.Conn.read_body(conn, DawarichWeb.RailsProxy.read_options()) do
      {:more, _bytes, conn} -> drain(conn)
      {:ok, _bytes, conn} -> conn
      {:error, reason} -> raise Plug.BadRequestError, message: inspect(reason)
    end
  end
end
