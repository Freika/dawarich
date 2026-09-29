defmodule DawarichWeb.LayoutAssigns do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.{RailsCsrf, RailsSession, RequestURL}

  def init(opts), do: opts

  def call(conn, _opts) do
    read = conn.assigns[:rails_session] || %{}
    changes = Map.merge(consume_flash(read), create_csrf(read))
    session = read |> Map.merge(changes) |> Map.reject(fn {_key, value} -> is_nil(value) end)
    conn = if changes == %{}, do: conn, else: RailsSession.stage(conn, changes)

    conn
    |> assign(:rails_session, session)
    |> assign(:self_hosted, self_hosted?())
    |> assign(:now, DateTime.utc_now())
    |> assign(:request_path, safe_path(conn.request_path))
    |> assign(:query_params, conn.query_params)
    |> assign(:base_url, RequestURL.base(conn))
    |> assign(:flash_messages, flashes(read))
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

  defp flashes(%{"flash" => %{"flashes" => flashes} = flash}) when is_map(flashes),
    do: flashes |> Map.drop(List.wrap(flash["discard"])) |> Map.to_list()

  defp flashes(_session), do: []

  defp consume_flash(%{"flash" => _flash}), do: %{"flash" => nil}
  defp consume_flash(_session), do: %{}

  defp create_csrf(%{"_csrf_token" => token}) when is_binary(token), do: %{}
  defp create_csrf(_session), do: %{"_csrf_token" => RailsCsrf.new_token()}

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
