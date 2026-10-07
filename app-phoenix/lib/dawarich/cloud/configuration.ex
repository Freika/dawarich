defmodule Dawarich.Cloud.Configuration do
  @moduledoc false

  def check(env) do
    if Dawarich.ReleaseMigration.self_hosted?(env), do: :ok, else: manager(env)
  end

  def validate!(env) do
    case check(env) do
      :ok -> :ok
      {:error, {:cloud_configuration, message}} -> raise ArgumentError, message
    end
  end

  def manager(env) do
    with :ok <- required(env, "MANAGER_URL"),
         :ok <- secure_origin(env["MANAGER_URL"]),
         :ok <- required(env, "JWT_SECRET_KEY"),
         do: :ok
  end

  def required(env, key) do
    case env[key] do
      value when is_binary(value) ->
        if String.trim(value) != "", do: :ok, else: missing(key)

      _ ->
        missing(key)
    end
  end

  def manager_origin?(base), do: Dawarich.Cloud.EndpointURL.origin?(base)

  defp secure_origin(base) do
    if manager_origin?(base),
      do: :ok,
      else:
        {:error,
         {:cloud_configuration,
          "Cloud configuration: MANAGER_URL must be an HTTPS origin without credentials, path, query or fragment"}}
  end

  defp missing(key),
    do:
      {:error,
       {:cloud_configuration, "Cloud configuration: #{key} is required and must not be blank"}}
end
