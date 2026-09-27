defmodule Dawarich.RailsSecret do
  @moduledoc false

  @local_envs ["development", "test"]
  @endpoint_salt "dawarich phoenix endpoint"

  def rails_env(env) do
    Enum.find_value(["RAILS_ENV", "RACK_ENV"], "development", fn name ->
      case env[name] do
        value when value in [nil, ""] -> nil
        value -> value
      end
    end)
  end

  def resolve(env, rails_root) do
    case env["SECRET_KEY_BASE"] do
      secret when is_binary(secret) and secret != "" -> secret
      _ -> if rails_env(env) in @local_envs, do: read_local(rails_root)
    end
  end

  def fetch do
    Application.get_env(:dawarich, :rails_secret) || cached()
  end

  def endpoint_secret(nil), do: Base.encode64(:crypto.strong_rand_bytes(64))

  def endpoint_secret(rails_secret) do
    rails_secret
    |> Plug.Crypto.KeyGenerator.generate(@endpoint_salt,
      iterations: 1000,
      length: 64,
      digest: :sha256
    )
    |> Base.encode64()
  end

  defp cached do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> remember(resolve(System.get_env(), File.cwd!()))
      secret -> secret
    end
  end

  defp remember(nil), do: nil

  defp remember(secret) do
    :persistent_term.put(__MODULE__, secret)
    secret
  end

  defp read_local(root) do
    case File.read(Path.join(root, "tmp/local_secret.txt")) do
      {:ok, secret} when secret != "" -> secret
      _ -> nil
    end
  end
end
