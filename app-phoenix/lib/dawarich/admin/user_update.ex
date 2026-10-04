defmodule Dawarich.Admin.UserUpdate do
  @moduledoc false
  alias Dawarich.Admin.{UserRoles, UserValidation}
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.Settings
  alias Dawarich.Repo
  @rounds if(Mix.env() == :test, do: 4, else: 12)

  def call(actor, id, params, context) do
    repo = Map.get(context, :repo, Repo)

    with :ok <- authorize(actor, repo, context),
         {:ok, target} <- target(repo, id),
         :ok <- UserRoles.guard(target, params, repo, Map.get(context, :locale, "en")),
         {:ok, settings} <- sanitize(target.settings),
         {:ok, changes} <-
           UserValidation.update(
             target,
             params,
             validation_context(target, params, repo, context)
           ) do
      changes =
        if settings == target.settings, do: changes, else: Map.put(changes, :settings, settings)

      persist(repo, id, credentials(changes), context)
    end
  end

  defp authorize(actor, repo, context) do
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

  defp target(repo, id) when is_integer(id) and id > 0 do
    case repo.query!(
           "SELECT email,admin,status,settings,encrypted_password FROM users WHERE id=$1 AND deleted_at IS NULL",
           [id],
           log: false
         ).rows do
      [[email, admin, status, settings, hash]] when is_binary(hash) and byte_size(hash) >= 29 ->
        {:ok,
         %{
           id: id,
           email: email,
           admin: admin,
           status: status,
           settings: settings,
           encrypted_password: hash
         }}

      _ ->
        {:handoff, :target}
    end
  end

  defp target(_, _), do: {:handoff, :target}

  defp sanitize(settings) do
    case Settings.sanitize(settings) do
      {:ok, value} -> {:ok, value}
      _ -> {:handoff, :settings_callback}
    end
  end

  defp validation_context(target, params, repo, context) do
    email = Account.normalize_email(Map.get(params, "email", target.email) || "")

    [[taken]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM users WHERE email=$1 AND id<>$2)",
        [email, target.id],
        log: false
      ).rows

    Map.put(context, :email_taken, taken)
  end

  defp credentials(changes) do
    {password, changes} = Map.pop(changes, :password)

    changes =
      if password do
        bytes = binary_part(password, 0, min(byte_size(password), 72))
        Map.put(changes, :encrypted_password, Bcrypt.hash_pwd_salt(bytes, log_rounds: @rounds))
      else
        changes
      end

    if Map.has_key?(changes, :email) or Map.has_key?(changes, :encrypted_password),
      do: Map.merge(changes, %{reset_password_token: nil, reset_password_sent_at: nil}),
      else: changes
  end

  defp persist(_repo, id, changes, _context) when map_size(changes) == 0, do: {:ok, id}

  defp persist(repo, id, changes, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()
    values = Map.put(changes, :updated_at, now) |> Enum.sort()

    sets =
      Enum.with_index(values, 1) |> Enum.map_join(",", fn {{key, _}, n} -> "#{key}=$#{n}" end)

    result =
      repo.query!(
        "UPDATE users SET #{sets} WHERE id=$#{length(values) + 1}",
        Enum.map(values, &elem(&1, 1)) ++ [id],
        log: false
      )

    if result.num_rows == 1, do: {:ok, id}, else: {:terminal, :target}
  end
end
