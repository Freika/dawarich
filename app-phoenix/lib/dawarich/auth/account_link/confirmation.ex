defmodule Dawarich.Auth.AccountLink.Confirmation do
  @moduledoc false
  alias Dawarich.Auth.AccountLink.Pending
  alias Dawarich.Repo

  def commit(prepared, context) do
    changes = %{
      provider: prepared.pending["provider"],
      uid: prepared.pending["uid"],
      updated_at: Map.get(context, :clock, &DateTime.utc_now/0).()
    }

    user =
      prepared.user
      |> Ecto.Changeset.change(changes)
      |> Map.get(context, :repo, Repo).update!(log: false)

    session = Map.drop(prepared.session, ~w(pending_oauth_link pending_oauth_link_attempts))
    kind = if user.otp_required_for_login, do: :link_only, else: :sign_in
    {:ok, Map.merge(prepared, %{user: user, session: session, kind: kind})}
  end

  def prepare(session, password, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()

    with {:ok, prepared} <- Pending.valid(session, now, context),
         true <- supported_password?(password),
         true <- verify(password, prepared.user.encrypted_password) do
      {:ok, prepared}
    else
      false -> {:handoff, :password}
      {:handoff, _} = result -> result
    end
  end

  defp supported_password?(password) when is_binary(password),
    do: password != "" and String.valid?(password) and not String.contains?(password, <<0>>)

  defp supported_password?(_), do: false

  defp verify(password, hash),
    do: Bcrypt.verify_pass(binary_part(password, 0, min(byte_size(password), 72)), hash)
end
