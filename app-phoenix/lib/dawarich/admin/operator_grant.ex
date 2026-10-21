defmodule Dawarich.Admin.OperatorGrant do
  @moduledoc false

  @prefix "dawarich:operator_grant:"
  @ttl 3600

  def store(user, login, grant),
    do:
      Dawarich.Redis.cache_command([
        "SET",
        @prefix <> grant,
        binding(user, login),
        "EX",
        Integer.to_string(@ttl)
      ])

  def authorized?(user, %{"operator_grant" => grant, "operator_login" => login})
      when is_binary(grant) and byte_size(grant) == 43 and is_binary(login) do
    with true <- operator?(user),
         {:ok, value} when is_binary(value) <-
           Dawarich.Redis.cache_command(["GET", @prefix <> grant]) do
      Plug.Crypto.secure_compare(value, binding(user, login))
    else
      _ -> false
    end
  end

  def authorized?(_user, _context), do: false

  def operator?(%{admin: true}), do: Dawarich.ReleaseMigration.self_hosted?() or configured?()
  def operator?(_), do: false

  def configured?,
    do:
      present?(System.get_env("SIDEKIQ_USERNAME")) and
        present?(System.get_env("SIDEKIQ_PASSWORD"))

  def digest(value),
    do:
      :crypto.mac(:hmac, :sha256, Dawarich.RailsSecret.fetch(), :erlang.term_to_binary(value))
      |> Base.url_encode64(padding: false)

  defp binding(user, login),
    do:
      digest(
        {user.id, login, System.get_env("SIDEKIQ_USERNAME"), System.get_env("SIDEKIQ_PASSWORD")}
      )

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
