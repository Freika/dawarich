defmodule Dawarich.Auth.Recovery.Lifecycle do
  @moduledoc "Transactional recovery state; HTTP sign-in and delivery remain separate boundaries."
  import Ecto.Query
  alias Dawarich.Accounts
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Notification, Settings, Token}
  alias Dawarich.{RailsSecret, Repo}

  def request_reset(email, context \\ %{}), do: request(email, :reset_password_token, context)
  def request_unlock(email, context \\ %{}), do: request(email, :unlock_token, context)

  defp request(email, column, context) when is_binary(email) do
    keyed(context, column, fn repo, context ->
      email = Account.normalize_email(email)

      user = repo.one(from u in accounts(), where: u.email == ^email, lock: "FOR UPDATE")

      cond do
        is_nil(user) ->
          {:error, :not_found}

        column == :unlock_token and not locked?(user, now(context)) ->
          {:error, :not_locked}

        true ->
          case Settings.sanitize(user.settings) do
            {:ok, settings} -> issue(repo, user, column, settings, context)
            :error -> {:handoff, :settings_callback}
          end
      end
    end)
  end

  defp request(_, _, _), do: {:handoff, :parameters}

  defp issue(repo, user, column, settings, context) do
    {raw, digest} = fresh_token(repo, column, context)
    changes = %{column => digest, :updated_at => now(context)}

    changes =
      if column == :reset_password_token,
        do: Map.put(changes, :reset_password_sent_at, now(context)),
        else: changes

    changes =
      if settings == user.settings, do: changes, else: Map.put(changes, :settings, settings)

    user = change(repo, user, changes)

    kind =
      if column == :reset_password_token,
        do: :reset_password_instructions,
        else: :unlock_instructions

    {:ok, %{user: user, notification: intent(user, kind, raw, digest, context)}}
  end

  def reset(raw, password, confirmation, context \\ %{})

  def reset(raw, password, confirmation, %{self_hosted: true} = context) do
    keyed(context, :reset_password_token, fn repo, context ->
      case find_token(repo, :reset_password_token, raw, context) do
        nil ->
          {:error, Token.token_error(raw)}

        user ->
          cond do
            callbacks(user) != :ok ->
              {:handoff, :settings_callback}

            user.status == 3 ->
              {:handoff, :payment}

            is_nil(user.reset_password_sent_at) or
                DateTime.compare(user.reset_password_sent_at, DateTime.add(now(context), -21_600)) ==
                  :lt ->
              {:error, :expired}

            true ->
              reset_user(repo, user, password, confirmation, context)
          end
      end
    end)
  end

  def reset(_, _, _, _), do: {:handoff, :password_change_notification}

  defp reset_user(repo, user, password, confirmation, context) do
    case validate_password(password, confirmation) do
      :ok ->
        bytes = binary_part(password, 0, min(byte_size(password), 72))
        hash = Bcrypt.hash_pwd_salt(bytes, log_rounds: Map.get(context, :log_rounds, 12))

        changes = %{
          encrypted_password: hash,
          reset_password_token: nil,
          reset_password_sent_at: nil,
          failed_otp_attempts: 0,
          otp_locked_at: nil,
          failed_attempts: 0,
          locked_at: nil,
          unlock_token: nil,
          updated_at: now(context)
        }

        changes =
          case Map.get(context, :sign_in_ip) do
            ip when is_binary(ip) ->
              Map.merge(changes, Dawarich.Auth.Trackable.changes(user, now(context), ip))

            nil ->
              changes
          end

        {:ok, change(repo, user, changes)}

      other ->
        other
    end
  end

  def unlock(raw, context \\ %{}) do
    keyed(context, :unlock_token, fn repo, context ->
      case find_token(repo, :unlock_token, raw, context) do
        nil ->
          {:error, Token.token_error(raw)}

        user ->
          with :ok <- callbacks(user) do
            {:ok,
             change(repo, user, %{
               locked_at: nil,
               failed_attempts: 0,
               unlock_token: nil,
               updated_at: now(context)
             })}
          end
      end
    end)
  end

  defp find_token(repo, column, raw, context) do
    case Token.digest(column, raw, secret(context)) do
      digest when is_binary(digest) ->
        repo.one(from u in accounts(), where: field(u, ^column) == ^digest)

      _ ->
        nil
    end
  end

  defp validate_password(password, confirmation) when is_binary(password) do
    length = password |> String.codepoints() |> Kernel.length()

    checks = [
      confirmation: confirmation != nil and confirmation != password,
      too_short: length < 12,
      too_long: length > 128
    ]

    cond do
      not String.valid?(password) or String.contains?(password, <<0>>) -> {:handoff, :parameters}
      Token.blank?(password) -> {:error, {:validation, [:blank]}}
      Keyword.values(checks) == [false, false, false] -> :ok
      true -> {:error, {:validation, for({kind, true} <- checks, do: kind)}}
    end
  end

  defp validate_password(_, _), do: {:error, {:validation, [:blank]}}

  defp fresh_token(repo, column, context) do
    raw = Map.get(context, :token_generator, &Token.raw/0).()
    digest = Token.digest(column, raw, secret(context))

    if repo.exists?(
         from u in Account, where: field(u, ^column) == ^digest and is_nil(u.deleted_at)
       ) do
      fresh_token(repo, column, context)
    else
      {raw, digest}
    end
  end

  defp callbacks(user),
    do:
      if(Settings.sanitize(user.settings) == {:ok, user.settings},
        do: :ok,
        else: {:handoff, :settings_callback}
      )

  defp accounts do
    from u in Account,
      where: is_nil(u.deleted_at),
      select_merge: %{
        settings:
          fragment("CASE WHEN jsonb_typeof(?) = 'object' THEN ? END", u.settings, u.settings)
      }
  end

  defp locked?(user, now), do: not Accounts.unlocked?(user, now)

  defp intent(user, kind, raw, digest, context) do
    locale = DawarichWeb.Locale.resolve(nil, user, %{"locale" => Map.get(context, :locale, "en")})
    %Notification{kind: kind, user_id: user.id, raw: raw, digest: digest, locale: locale}
  end

  defp keyed(context, column, fun) do
    case secret(context) do
      secret when is_binary(secret) ->
        Token.key(column, secret)
        context = Map.put(context, :secret, secret)
        repo = Map.get(context, :repo, Repo)
        {:ok, result} = repo.transaction(fn -> fun.(repo, context) end)
        result

      _ ->
        {:handoff, :secret}
    end
  end

  defp change(repo, user, changes), do: repo.update!(Ecto.Changeset.change(user, changes))
  defp now(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
end
