defmodule Dawarich.Auth.RegistrationSetting do
  @moduledoc false

  alias Dawarich.{Repo, State}

  def fetch(env \\ System.get_env(), repo \\ Repo) do
    case repo.transaction(fn ->
           initialized!(repo, "FOR SHARE")
           State.registration_enabled(repo, env["ALLOW_EMAIL_PASSWORD_REGISTRATION"] == "true")
         end) do
      {:ok, value} -> {:ok, value}
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _ -> :error
  end

  def put(value, repo \\ Repo) when value in [true, false, nil] do
    case repo.transaction(fn ->
           initialized!(repo, "FOR UPDATE")
           State.put_registration_enabled(repo, value)
         end) do
      {:ok, :ok} -> :ok
      _ -> {:error, :database}
    end
  rescue
    _ -> {:error, :database}
  catch
    _ -> {:error, :database}
  end

  defp initialized!(repo, lock) do
    case repo.query!("SELECT id FROM phoenix.registration_setting WHERE id = true " <> lock, [],
           log: false
         ).rows do
      [[true]] -> :ok
      [] -> repo.rollback(:incomplete_registration_copy)
    end
  end
end
