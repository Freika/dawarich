defmodule DawarichWeb.FamilyRequestAdmission do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{RailsProxy, Router}
  alias DawarichWeb.Api.Body

  def init(opts), do: opts

  def call(%{method: "GET"} = conn, _opts), do: conn

  def call(conn, _opts) do
    cond do
      invalid_escape?(conn.query_string) ->
        Body.replay(conn, "family query encoding")

      get_req_header(conn, "x-http-method-override") != [] ->
        Body.replay(conn, "family method override header")

      Body.kind(conn) not in [:none, :form, :json] ->
        Body.replay(conn, "family body type")

      true ->
        admit_body(conn)
    end
  end

  def read_body(%{private: %{dawarich_raw_body: raw}} = conn, _opts), do: {:ok, raw, conn}
  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  defp admit_body(conn) do
    case read(conn, []) do
      {:ok, raw, conn} ->
        conn = put_private(conn, :dawarich_raw_body, raw)

        if Body.kind(conn) == :form and
             (invalid_escape?(raw) or not supported_method?(conn, raw)),
           do: Body.replay(conn, "family form encoding or method"),
           else: conn

      {:error, conn} ->
        conn |> send_resp(400, "") |> halt()
    end
  end

  defp read(%{private: %{dawarich_raw_body: raw}} = conn, []), do: {:ok, raw, conn}

  defp read(conn, acc) do
    case Plug.Conn.read_body(conn, RailsProxy.read_options()) do
      {:ok, raw, conn} -> {:ok, IO.iodata_to_binary([acc, raw]), conn}
      {:more, raw, conn} -> read(conn, [acc, raw])
      {:error, _} -> {:error, conn}
    end
  end

  defp supported_method?(%{method: "POST"} = conn, raw) do
    case Plug.Conn.Query.decode(raw)["_method"] do
      nil ->
        true

      method when is_binary(method) ->
        case Phoenix.Router.route_info(Router, String.upcase(method), conn.path_info, conn.host) do
          %{plug: DawarichWeb.FamilyFormRoutes} -> true
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp supported_method?(_conn, _raw), do: true
  defp invalid_escape?(value), do: Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, value)
end
