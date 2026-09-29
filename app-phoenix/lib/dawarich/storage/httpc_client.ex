defmodule Dawarich.Storage.HttpcClient do
  @moduledoc false
  @behaviour ExAws.Request.HttpClient

  @options [connect_timeout: 60_000, timeout: 600_000]

  @impl ExAws.Request.HttpClient
  def request(method, url, body, headers, _http_opts) do
    {content_type, headers} =
      Enum.split_with(headers, fn {name, _} -> String.downcase(name) == "content-type" end)

    headers = for {name, value} <- headers, do: {to_charlist(name), to_charlist(value)}
    options = [ssl: Dawarich.Http.ssl_options()] ++ @options

    request =
      if method in [:put, :post] do
        {to_charlist(url), headers, content_type(content_type), body}
      else
        {to_charlist(url), headers}
      end

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_, status, _}, response_headers, response_body}} ->
        {:ok,
         %{
           status_code: status,
           headers:
             for({name, value} <- response_headers, do: {to_string(name), to_string(value)}),
           body: response_body
         }}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  defp content_type([{_, value} | _]), do: to_charlist(value)
  defp content_type([]), do: ~c"application/octet-stream"
end
