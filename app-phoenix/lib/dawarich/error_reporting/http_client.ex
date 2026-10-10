defmodule Dawarich.ErrorReporting.HttpClient do
  @behaviour Sentry.HTTPClient

  @impl true
  def post(url, headers, body) do
    headers =
      for {key, value} <- headers, do: {String.to_charlist(key), String.to_charlist(value)}

    request = {String.to_charlist(url), headers, ~c"application/x-sentry-envelope", body}

    case :httpc.request(
           :post,
           request,
           [
             connect_timeout: 1_000,
             timeout: 2_000,
             autoredirect: false,
             ssl: Dawarich.Http.ssl_options()
           ],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, headers, body}} ->
        {:ok, status, for({key, value} <- headers, do: {to_string(key), to_string(value)}), body}

      {:error, _} ->
        {:error, :transport_unavailable}
    end
  end
end
