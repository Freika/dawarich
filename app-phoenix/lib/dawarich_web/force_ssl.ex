defmodule DawarichWeb.ForceSSL do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.RailsSecret
  alias DawarichWeb.RackScheme

  @hsts "max-age=63072000; includeSubDomains"
  @env ~w(APPLICATION_PROTOCOL RAILS_ENV RACK_ENV)

  def hsts, do: @hsts

  def enabled?(env \\ Map.new(@env, &{&1, System.get_env(&1)})) do
    String.downcase(env["APPLICATION_PROTOCOL"] || "http") == "https" and
      RailsSecret.rails_env(env) != "test"
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      not enabled?() ->
        conn

      RackScheme.ssl?(conn) ->
        conn |> as_https() |> put_resp_header("strict-transport-security", @hsts)

      true ->
        redirect(conn)
    end
  end

  defp as_https(%{port: 80} = conn), do: %{conn | scheme: :https, port: 443}
  defp as_https(conn), do: %{conn | scheme: :https}

  defp redirect(conn) do
    status = if conn.method in ~w(GET HEAD), do: 301, else: 308

    conn
    |> put_resp_header("location", location(conn))
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end

  defp location(conn) do
    base = conn |> as_https() |> DawarichWeb.RequestURL.base() |> String.replace(~r/:80\z/, "")
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    base <> conn.request_path <> query
  end
end
