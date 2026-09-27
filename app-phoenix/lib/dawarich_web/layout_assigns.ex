defmodule DawarichWeb.LayoutAssigns do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.RailsCsrf

  def init(opts), do: opts

  def call(conn, _opts) do
    session = conn.assigns[:rails_session] || %{}

    flashes =
      case session["flash"] do
        %{"flashes" => flashes} when is_map(flashes) -> Map.to_list(flashes)
        _ -> []
      end

    conn
    |> assign(:self_hosted, self_hosted?())
    |> assign(:now, DateTime.utc_now())
    |> assign(:request_path, safe_path(conn.request_path))
    |> assign(:query_params, conn.query_params)
    |> assign(:flash_messages, flashes)
    |> assign(:rails_csrf_token, RailsCsrf.masked_token(session))
  end

  def self_hosted?(env \\ System.get_env()) do
    case env["SELF_HOSTED"] do
      nil ->
        true

      value when is_binary(value) ->
        value
        |> String.replace(~r/["']/, "")
        |> String.trim()
        |> String.downcase()
        |> then(&(&1 in ~w(true 1 yes on t)))

      _ ->
        false
    end
  end

  defp safe_path(path) do
    path
    |> to_string()
    |> String.replace(~r/[^\w\-.~!$&'()*+,;=:@%\/]/, "")
    |> String.replace(~r/^\/+/, "/")
    |> case do
      "" -> "/"
      value -> value
    end
  end
end
