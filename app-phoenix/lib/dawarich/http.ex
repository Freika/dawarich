defmodule Dawarich.Http do
  @moduledoc false

  def ssl_options("https:" <> _) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  def ssl_options(_url), do: []

  def get(url, headers) do
    request =
      {String.to_charlist(url),
       for({name, value} <- headers, do: {String.to_charlist(name), String.to_charlist(value)})}

    case :httpc.request(
           :get,
           request,
           [connect_timeout: 5_000, timeout: 5_000, ssl: ssl_options(url)],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
      {:error, _reason} -> :error
    end
  end
end
