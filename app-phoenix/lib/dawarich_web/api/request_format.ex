defmodule DawarichWeb.Api.RequestFormat do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  @formats %{
    "json" => :json,
    "html" => :html,
    "xml" => :xml,
    "text" => :text,
    "jpg" => :jpeg,
    "jpeg" => :jpeg,
    "mvt" => :mvt,
    "js" => :js
  }
  @types %{
    "application/json" => :json,
    "text/x-json" => :json,
    "application/jsonrequest" => :json,
    "text/html" => :html,
    "application/xhtml+xml" => :html,
    "application/xml" => :xml,
    "text/xml" => :xml,
    "text/plain" => :text,
    "*/*" => :all
  }

  def init(opts), do: opts

  def call(%{path_info: ["api", "v1" | rest]} = conn, _opts) do
    if DawarichWeb.Strangler.handed_back?(conn.path_info) or Enum.take(rest, 1) == ["tiles"] do
      conn
    else
      last = List.last(rest) || ""

      case Regex.run(~r/\A(.+)\.([^\.\/]+)\z/, last) do
        [_, name, format] ->
          conn
          |> put_private(:dawarich_path_format, format)
          |> put_private(:dawarich_original_path_info, conn.path_info)
          |> Map.put(:path_info, List.replace_at(conn.path_info, -1, name))

        _ ->
          conn
      end
    end
  end

  def call(conn, _opts), do: conn

  def decide(conn) do
    format = conn.private[:dawarich_path_format] || conn.assigns.api_params["format"]

    cond do
      is_binary(format) -> {:ok, Map.get(@formats, format, :unknown), false}
      format not in [nil, false] -> {:error, 400}
      true -> accept(conn)
    end
  end

  defp accept(conn) do
    value = conn |> get_req_header("accept") |> Enum.join(", ")

    cond do
      String.trim(value) == "" ->
        {:ok, if(get_req_header(conn, "x-requested-with") == [], do: :html, else: :js), false}

      DawarichWeb.Strangler.browser_like?(value) ->
        {:ok, :html, false}

      true ->
        negotiate(value)
    end
  end

  defp negotiate(value) do
    choices =
      value
      |> String.split(",")
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        [type | params] = String.split(String.trim(entry), ";")
        if not Regex.match?(~r/\A[\w!#$&^.+*\-]+\/[\w!#$&^.+*\-]+\z/, type), do: throw(:invalid)

        quality =
          Enum.find_value(params, 1.0, fn param ->
            case String.split(String.trim(param), "=", parts: 2) do
              ["q", q] ->
                case Float.parse(q) do
                  {n, ""} -> n
                  _ -> 0.0
                end

              _ ->
                nil
            end
          end)

        {quality, -index, Map.get(@types, type, :unknown)}
      end)

    {_, _, format} = Enum.max(choices)
    {:ok, format, true}
  catch
    :invalid -> {:error, 400}
  end
end
