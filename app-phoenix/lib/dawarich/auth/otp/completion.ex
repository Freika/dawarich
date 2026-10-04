defmodule Dawarich.Auth.Otp.Completion do
  @moduledoc false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.Trackable
  alias Dawarich.Auth.Otp.{Pending, Start}
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Secret, Totp}

  def commit(prepared, context), do: commit_saves(prepared, context)

  defp commit_saves(prepared, context) do
    ip = Map.fetch!(context, :ip)
    user = save(prepared.user, prepared.changes, context)
    user = reset_otp(user, context)

    user =
      if prepared.remember and is_nil(user.remember_created_at),
        do: save(user, %{remember_created_at: clock(context)}, context),
        else: user

    user =
      if user.failed_attempts != 0, do: save(user, %{failed_attempts: 0}, context), else: user

    user = save(user, Trackable.changes(user, clock(context), ip), context)

    remember =
      if prepared.remember,
        do: [
          [user.id],
          binary_part(user.encrypted_password, 0, 29),
          Accounts.remember_generated_at(clock(context))
        ]

    {:ok, %{user: user, remember: remember, session: prepared.session}}
  end

  defp reset_otp(user, context) do
    if user.failed_otp_attempts != 0 or not is_nil(user.otp_locked_at) do
      changeset =
        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.force_change(:failed_otp_attempts, 0)
        |> Ecto.Changeset.force_change(:otp_locked_at, nil)

      Map.get(context, :repo, Repo).update!(changeset, log: false)
    else
      user
    end
  end

  defp save(user, changes, context) do
    user
    |> Ecto.Changeset.change(Map.put(changes, :updated_at, clock(context)))
    |> Map.get(context, :repo, Repo).update!(log: false)
  end

  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()

  def prepare(session, code, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    case Pending.valid(session, DateTime.to_unix(now)) do
      :expired -> {:expired, Pending.clear(session)}
      {:handoff, _} = refusal -> refusal
      {:ok, id, remember} -> prepare_actor(session, id, remember, code, now, context)
    end
  end

  defp prepare_actor(session, id, remember, code, now, context) do
    case Start.actor(id, context) do
      :missing ->
        {:expired, Pending.clear(session)}

      {:handoff, _} = refusal ->
        refusal

      {:ok, user} ->
        env = Map.get_lazy(context, :env, &System.get_env/0)

        with {:ok, secret} <- Secret.decrypt(user.otp_secret, env),
             :ok <- supported(user, secret, code),
             {:ok, kind, changes} <- select(user, secret, code, now, context) do
          {:ok,
           %{
             user: user,
             kind: kind,
             changes: changes,
             remember: remember,
             session: Pending.clear(session)
           }}
        end
    end
  end

  defp supported(user, secret, code) do
    cond do
      not is_binary(code) or String.contains?(code, <<0>>) ->
        {:handoff, :parameters}

      not is_integer(user.failed_otp_attempts) ->
        {:handoff, :counter_state}

      not BackupCodes.supported?(user.otp_backup_codes) ->
        {:handoff, :backup_state}

      not is_binary(secret) ->
        {:handoff, :secret}

      true ->
        Totp.decode(secret)
        :ok
    end
  rescue
    ArgumentError -> {:handoff, :secret}
  end

  defp select(user, secret, code, now, context) do
    if user.otp_locked_at && DateTime.compare(user.otp_locked_at, DateTime.add(now, -1800)) == :gt do
      backup(user, code, context)
    else
      case Totp.verify(secret, code, DateTime.to_unix(now), user.consumed_timestep) do
        {:ok, timestep} -> {:ok, :totp, %{consumed_timestep: timestep}}
        :invalid -> backup(user, code, context)
      end
    end
  end

  defp backup(user, code, context) do
    case BackupCodes.consume(user.otp_backup_codes, code, Map.get(context, :backup_options, [])) do
      {:ok, hashes} -> {:ok, :backup, %{otp_backup_codes: hashes}}
      :invalid -> {:handoff, :invalid_code}
      {:handoff, _} = refusal -> refusal
    end
  end
end
