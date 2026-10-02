defmodule Dawarich.Geocoding.Http do
  @moduledoc false

  @options [connect_timeout: 5_000, timeout: 5_000, autoredirect: false]

  def get(url, headers),
    do: Application.get_env(:dawarich, :geocoding_http, __MODULE__).request(url, headers)

  def request(url, headers) do
    request =
      {String.to_charlist(url),
       for({k, v} <- headers, do: {String.to_charlist(k), String.to_charlist(v)})}

    case :httpc.request(:get, request, [ssl: Dawarich.Http.ssl_options()] ++ @options,
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
      {:error, :timeout} -> {:error, :timeout}
      {:error, {:failed_connect, [_, {_, _, :econnrefused}]}} -> {:error, :econnrefused}
      {:error, {:failed_connect, [_, {_, _, :nxdomain}]}} -> {:error, :nxdomain}
      {:error, {:failed_connect, [_, {_, _, {:tls_alert, _}}]}} -> {:error, :tls}
      {:error, _reason} -> {:error, :network}
    end
  end
end
