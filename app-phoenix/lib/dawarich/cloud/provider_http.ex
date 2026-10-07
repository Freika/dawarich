defmodule Dawarich.Cloud.ProviderHTTP do
  @moduledoc false
  alias Dawarich.Photos.ProviderHTTP, as: Transport

  @test_loopback Application.compile_env(:dawarich, :cloud_test_loopback, false)

  @paths %{
    manager: ["/api/v1/users", "/api/v1/users/unlink"],
    partnero: ["/v1/customers"]
  }

  def post(provider, path, headers, encoded_body, opts \\ []) do
    with :ok <- provider?(provider),
         :ok <- path?(provider, path),
         {:ok, origin} <- origin(provider, opts) do
      transport = Keyword.get(opts, :transport, &Transport.request/8)

      opts = Keyword.put(opts, :total_timeout, 10_000)

      case transport.(:post, origin, path, headers, encoded_body, false, 10_000, opts) do
        {:ok, status, _headers, body} ->
          {:ok, status, body}

        {:error, reason} when reason in [:timeout, :connect_timeout, :too_large, :connection] ->
          {:error, reason}

        _ ->
          {:error, :transport}
      end
    end
  rescue
    _ -> {:error, :transport}
  catch
    _, _ -> {:error, :transport}
  end

  defp provider?(provider),
    do: if(Map.has_key?(@paths, provider), do: :ok, else: {:error, :invalid_provider})

  defp path?(provider, path),
    do: if(path in @paths[provider], do: :ok, else: {:error, :invalid_path})

  defp origin(:partnero, _opts), do: {:ok, "https://api.partnero.com"}

  defp origin(:manager, opts) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)
    base = env["MANAGER_URL"]

    if Dawarich.Cloud.Configuration.manager_origin?(base) or test_loopback?(base, opts),
      do: {:ok, base},
      else: {:error, :invalid_origin}
  end

  defp test_loopback?(base, opts) do
    @test_loopback and opts[:test_loopback] == true and Transport.base_url?(base) and
      URI.parse(base).scheme == "http" and URI.parse(base).host in ["127.0.0.1", "::1"] and
      URI.parse(base).path in [nil, ""]
  end
end
