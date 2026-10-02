defmodule Dawarich.Auth.Credentials do
  @moduledoc """
  Transactional credentials for the bounded A11 password slice.

  The password is checked before the row lock is taken; a hash that changed
  in between hands off. OTP, provider and payment accounts hand off only after
  a correct password, and new lock creation remains on its Rails boundary. A
  handoff commits no authentication effects. Invalid credentials commit the
  characterized strategy failure counters; they are not rollbacks.
  """

  import Ecto.Query
  alias Dawarich.Accounts
  alias Dawarich.Auth.{Account, RememberCredential, Trackable}
  alias Dawarich.Repo

  def login(email, password, context \\ %{})

  def login(email, password, context) when is_binary(email) and is_binary(password) do
    repo = Map.get(context, :repo, Repo)
    query = from(u in Account, where: u.email == ^normalize_email(email) and is_nil(u.deleted_at))

    case repo.one(query) do
      nil ->
        dummy(context)
        {:error, :invalid}

      %{encrypted_password: hash} = user ->
        valid = valid_password?(password, hash, context)

        {:ok, result} =
          repo.transaction(fn ->
            case repo.one(from(u in query, where: u.id == ^user.id, lock: "FOR UPDATE")) do
              %{encrypted_password: ^hash} = fresh ->
                authenticate(fresh, password, valid, context, repo)

              _ ->
                {:handoff, :changed}
            end
          end)

        result
    end
  end

  def login(_, _, _), do: {:handoff, :parameters}

  def logout(id, context \\ %{}) when is_integer(id) do
    repo = Map.get(context, :repo, Repo)

    {:ok, :ok} =
      repo.transaction(fn ->
        user =
          repo.one(
            from(u in Account, where: u.id == ^id and is_nil(u.deleted_at), lock: "FOR UPDATE")
          )

        if user && user.remember_created_at do
          change(repo, user, %{remember_created_at: nil, updated_at: clock(context)})
        end

        :ok
      end)

    :ok
  end

  def restore(payload, context \\ %{})

  def restore([[id], _token, _generated] = payload, context) when is_integer(id) do
    repo = Map.get(context, :repo, Repo)

    {:ok, result} =
      repo.transaction(fn ->
        user =
          repo.one(
            from(u in Account, where: u.id == ^id and is_nil(u.deleted_at), lock: "FOR UPDATE")
          )

        now = clock(context)

        if RememberCredential.valid?(user, payload, now) do
          user = if user.locked_at, do: unlock(repo, user, now), else: user
          signed_in(repo, user, Map.put(context, :remember, false))
        else
          {:error, :invalid}
        end
      end)

    result
  end

  def restore(_, _), do: {:error, :invalid}

  defp authenticate(user, password, valid, context, repo) do
    now = clock(context)
    locked = not Accounts.unlocked?(user, now)
    expired = not is_nil(user.locked_at) and not locked
    count = if expired, do: 0, else: user.failed_attempts
    accepted = valid and not locked

    cond do
      valid and user.otp_required_for_login ->
        {:handoff, :otp}

      not locked and count >= 8 ->
        {:handoff, :lock_creation}

      accepted and is_binary(user.provider) and user.provider != "" ->
        {:handoff, :provider}

      accepted and user.status == 3 ->
        {:handoff, :payment}

      true ->
        user = if expired, do: unlock(repo, user, now), else: user

        if accepted do
          signed_in(repo, user, context)
        else
          increment =
            if not locked and not user.otp_required_for_login and blank?(password),
              do: 1,
              else: 2

          change(repo, user, %{failed_attempts: user.failed_attempts + increment})
          {:error, :invalid}
        end
    end
  end

  defp signed_in(repo, user, context) do
    remembered_at =
      if Map.get(context, :remember, false), do: user.remember_created_at || clock(context)

    changes = Trackable.changes(user, clock(context), Map.fetch!(context, :ip))
    changes = Map.put(changes, :failed_attempts, 0)
    changes = Map.put(changes, :updated_at, clock(context))

    changes =
      if remembered_at, do: Map.put(changes, :remember_created_at, remembered_at), else: changes

    user = change(repo, user, changes)

    remember =
      if remembered_at do
        [
          [user.id],
          binary_part(user.encrypted_password, 0, 29),
          Accounts.remember_generated_at(clock(context))
        ]
      end

    {:ok, %{user: user, remember: remember}}
  end

  defp unlock(repo, user, now),
    do:
      change(repo, user, %{failed_attempts: 0, locked_at: nil, unlock_token: nil, updated_at: now})

  defp valid_password?(password, hash, context) do
    if blank?(password) or hash == "",
      do: dummy(context),
      else: Bcrypt.verify_pass(password, hash)
  end

  defp dummy(context), do: Bcrypt.no_user_verify(log_rounds: Map.get(context, :log_rounds, 12))
  defp blank?(password), do: String.trim(password) == ""
  defp change(repo, user, changes), do: repo.update!(Ecto.Changeset.change(user, changes))
  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()

  defp normalize_email(email) do
    email
    |> String.downcase()
    |> String.replace(~r/\A[\x00\t\n\v\f\r ]+|[\x00\t\n\v\f\r ]+\z/u, "")
  end
end
