defmodule Dawarich.Admin.InstanceWrites do
  @moduledoc false
  alias Dawarich.Admin.InstanceInput
  alias Dawarich.{ActiveRecordEncryption, Redis, Repo}
  alias Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry, as: Registry

  def call(actor, params, context) do
    repo = Map.get(context, :repo, Repo)
    env = Map.get(context, :env, System.get_env())

    with :ok <- actor(actor, repo, context),
         {:ok, key} <- encryption(params, env),
         {:ok, values} <- InstanceInput.prepare(params, resolved(repo, key), env, context.locale) do
      persist(values, repo, key, env, context)
    end
  end

  def test_geocoding(actor, context) do
    repo = Map.get(context, :repo, Repo)

    with :ok <- actor(actor, repo, context),
         do: Dawarich.Admin.GeocodingTest.call(repo, context)
  end

  defp actor(actor, repo, context) do
    cond do
      context[:self_hosted] != true ->
        {:handoff, :cloud}

      context[:oidc] == true ->
        {:handoff, :oidc}

      true ->
        case repo.query!("SELECT admin FROM users WHERE id=$1 AND deleted_at IS NULL", [actor.id],
               log: false
             ).rows do
          [[true]] -> :ok
          _ -> {:handoff, :actor}
        end
    end
  end

  defp encryption(params, env) do
    case ActiveRecordEncryption.key(env) do
      {:ok, key} ->
        {:ok, key}

      _ ->
        if Enum.any?(Map.get(params, "instance_settings", []), fn {name, raw} ->
             List.keymember?(Registry.current_definitions(), name, 0) and Registry.secret?(name) and
               String.trim(raw || "") != ""
           end),
           do: {:handoff, :encryption},
           else: {:ok, nil}
    end
  end

  defp resolved(repo, key) do
    Map.new(
      repo.query!("SELECT key,value,encrypted_value FROM instance_settings", [], log: false).rows,
      fn [name, value, encrypted] ->
        secret? =
          List.keymember?(Registry.current_definitions(), name, 0) and Registry.secret?(name)

        {name, if(secret?, do: decrypt(encrypted, key), else: value)}
      end
    )
  end

  defp decrypt(nil, _), do: nil
  defp decrypt(_, nil), do: nil

  defp decrypt(encrypted, key) do
    case ActiveRecordEncryption.decrypt(encrypted, key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp persist(values, repo, key, env, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()
    command = Map.get(context, :command, &Redis.command/1)

    refused =
      Enum.reduce(values, [], fn {name, value}, refused ->
        variable = Registry.env_var(name)

        if Registry.set?(env[variable]) do
          refused ++ [variable]
        else
          write(repo, name, value, key, now)
          publish(command, name)
          refused
        end
      end)

    if Enum.any?(values, fn {name, _} -> name in ~w(map_matching_enabled atlas_url) end),
      do: Dawarich.Experimental.refresh_map_matching(repo, env)

    {:ok, refused}
  rescue
    _ -> {:terminal, :persistence}
  end

  defp write(repo, name, value, key, now) do
    case repo.query!("SELECT encrypted_value FROM instance_settings WHERE key=$1", [name],
           log: false
         ).rows do
      [[encrypted]] when not is_nil(encrypted) ->
        if is_nil(key) or not match?({:ok, _}, ActiveRecordEncryption.decrypt(encrypted, key)) do
          repo.query!("UPDATE instance_settings SET encrypted_value=NULL WHERE key=$1", [name],
            log: false
          )
        end

      _ ->
        :ok
    end

    secret? = Registry.secret?(name)
    encrypted = if secret? and not is_nil(value), do: ActiveRecordEncryption.encrypt(value, key)
    plain = if secret?, do: nil, else: value
    column = if secret?, do: ",encrypted_value=EXCLUDED.encrypted_value", else: ""

    repo.query!(
      "INSERT INTO instance_settings(key,value,encrypted_value,created_at,updated_at) VALUES($1,$2,$3,$4,$4) ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=EXCLUDED.updated_at" <>
        column,
      [name, plain, encrypted, now],
      log: false
    )
  end

  defp publish(command, name) do
    command.(["PUBLISH", "dawarich:instance_settings", Jason.encode!(%{"key" => name})])
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
