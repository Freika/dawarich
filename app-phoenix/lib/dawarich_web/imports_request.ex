defmodule DawarichWeb.ImportsRequest do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.Api.Body
  alias DawarichWeb.{RailsForm, RailsProxy}

  @keys ~w(authenticity_token _method trust_source import_id)
  @import_keys ~w(name source)
  @rack_params 4_096

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case params(conn) do
      {:ok, conn} -> admit(conn)
      {:replay, conn, reason} -> Body.replay(conn, reason)
      {:halt, conn} -> halt(conn)
    end
  end

  defp admit(conn) do
    with :ok <- page(conn), :ok <- RailsForm.admission(conn) do
      put_resp_header(conn, "x-dawarich-handler", "phoenix-imports")
    else
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp params(%{query_string: query} = conn) when query != "",
    do: {:replay, conn, "query string"}

  defp params(conn) do
    case Body.kind(conn) do
      :none -> {:ok, assign_params(conn, %{})}
      :form -> read(conn, [])
      _ -> {:replay, conn, "request body"}
    end
  end

  defp read(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, data, conn} ->
        read(conn, [acc, data])

      {:ok, data, conn} ->
        decode(put_private(conn, :dawarich_raw_body, IO.iodata_to_binary([acc, data])))

      {:error, _reason} ->
        {:halt, conn}
    end
  end

  defp decode(conn) do
    raw = conn.private.dawarich_raw_body
    body = Plug.Conn.Query.decode(raw)

    if length(:binary.matches(raw, "&")) < @rack_params - 1 and Enum.all?(body, &field?/1),
      do: {:ok, assign_params(conn, body)},
      else: {:replay, conn, "parameter shape"}
  rescue
    Plug.Conn.InvalidQueryError -> {:replay, conn, "parameter shape"}
  end

  defp field?({"import", %{} = import}), do: Enum.all?(import, &import_field?/1)
  defp field?({key, value}), do: key in @keys and is_binary(value)

  defp import_field?({"files", files}) when is_list(files), do: Enum.all?(files, &is_binary/1)
  defp import_field?({key, value}), do: key in @import_keys and is_binary(value)

  defp assign_params(conn, body) do
    %{conn | body_params: body, params: Map.merge(body, conn.path_params)}
    |> assign(:api_query, %{})
    |> assign(:api_params, Map.delete(body, "_method"))
  end

  defp page(conn) do
    if Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "turbo-stream")),
      do: {:replay, "turbo stream"},
      else: :ok
  end
end
