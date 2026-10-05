defmodule Dawarich.Geocoding.Search do
  @moduledoc false

  alias Dawarich.Geocoding.{Http, Providers, Query, RateLimiter, ResponseCache}
  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @bandwidth "Bandwidth limit exceeded"
  @locationiq_errors %{
    "Invalid key" => :invalid_api_key,
    "Key not active - Please write to contact@unwiredlabs.com" => :request_denied,
    "Rate Limited" => :over_query_limit,
    "Unknown error - Please try again after some time" => :invalid_request
  }

  def reverse(%{enabled: false}, _coords, _opts), do: {:ok, []}

  def reverse(config, coords, opts) do
    if incomplete?(config) do
      {:ok, []}
    else
      {url, key, headers} = Query.build(config, coords, opts, version())
      RateLimiter.throttle(config, fn -> fetch(config, url, key, headers) end)
    end
  end

  defp incomplete?(c),
    do:
      (Providers.host_required?(c.provider) and Ruby.blank?(c.host)) or
        (Providers.api_key_required?(c.provider) and Ruby.blank?(c.api_key))

  defp fetch(config, url, key, headers) do
    case ResponseCache.get(key) do
      {:ok, body} -> decode(config.provider, body)
      _ -> request(config.provider, url, key, headers)
    end
  end

  defp request(provider, url, key, headers) do
    with {:ok, status, body} <- Http.get(url, headers),
         :ok <- status_error(status) do
      if status in 200..399, do: ResponseCache.put(key, body)
      decode(provider, body)
    end
  end

  defp status_error(400), do: {:error, :invalid_request}
  defp status_error(401), do: {:error, :request_denied}
  defp status_error(status) when status in [402, 429], do: {:error, :over_query_limit}
  defp status_error(503), do: {:error, :service_unavailable}
  defp status_error(_status), do: :ok

  defp decode(provider, body) when provider in [:nominatim, :locationiq] do
    if String.contains?(body, @bandwidth),
      do: {:error, :over_query_limit},
      else: json(provider, body)
  end

  defp decode(provider, body), do: json(provider, body)

  defp json(provider, body) do
    case Jason.decode(body) do
      {:ok, doc} -> results(provider, doc)
      {:error, _} -> {:error, :response_parse_error}
    end
  rescue
    Ruby.Error -> {:error, :unexpected_document}
  end

  defp results(_provider, doc) when doc in [nil, false], do: {:ok, []}

  defp results(:geoapify, doc) do
    if Ruby.index(doc, "statusCode") == 500,
      do: {:error, :invalid_request},
      else: features(doc)
  end

  defp results(:photon, doc), do: features(doc)

  defp results(:locationiq, doc) when not is_list(doc) do
    case @locationiq_errors[Ruby.index(doc, "error")] do
      nil -> {:ok, [doc]}
      code -> {:error, code}
    end
  end

  defp results(_provider, doc) when is_list(doc), do: {:ok, doc}
  defp results(_provider, doc), do: {:ok, [doc]}

  defp features(doc) do
    if Ruby.index(doc, "type") == "FeatureCollection" do
      case Ruby.index(doc, "features") do
        empty when empty in [nil, false] -> {:ok, []}
        list when is_list(list) -> {:ok, list}
        _other -> {:error, :unexpected_document}
      end
    else
      {:ok, []}
    end
  end

  defp version,
    do:
      :dawarich
      |> Application.get_env(:app_version_file, Dawarich.RailsRoot.join(".app_version"))
      |> File.read!()
      |> ReleaseMigration.ruby_strip()
end
