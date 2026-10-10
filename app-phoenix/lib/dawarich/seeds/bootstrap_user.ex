defmodule Dawarich.Seeds.BootstrapUser do
  @moduledoc false

  alias Dawarich.Admin.UserPersistence
  alias Dawarich.Auth.Account
  alias Dawarich.CLI.Users

  @email "demo@dawarich.app"
  @password "safepassword"

  def run(repo, opts \\ []) do
    env =
      Keyword.get_lazy(opts, :env, &System.get_env/0)
      |> Map.put_new("TIME_ZONE", "Europe/Berlin")

    if Dawarich.ReleaseMigration.self_hosted?(env) and
         repo.query!("SELECT NOT EXISTS (SELECT 1 FROM users WHERE deleted_at IS NULL)", [],
           log: false
         ).rows == [[true]] do
      now = Keyword.get_lazy(opts, :now, &NaiveDateTime.utc_now/0)

      hash =
        case Keyword.fetch(opts, :salt) do
          {:ok, salt} -> Users.hash_password(@password, salt)
          :error -> Users.hash_password(@password)
        end

      attributes = [
        admin: true,
        status: 1,
        active_until: UserPersistence.expiry(repo, now, 100, env)
      ]

      attributes = attributes ++ Keyword.take(opts, [:random_bytes])

      case UserPersistence.insert(repo, Account.normalize_email(@email), hash, now, attributes) do
        {:ok, id} -> UserPersistence.activate(repo, id, now, %{}, env)
        {:error, :unique} -> raise ArgumentError, "initial administrator could not be created"
      end
    end

    :ok
  end
end
