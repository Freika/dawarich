defmodule Dawarich.Auth.TwoFactor.BackupCodes do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Token
  @rounds if(Mix.env() == :test, do: 4, else: 12)

  def generate(opts \\ []) do
    entropy = Keyword.get(opts, :entropy, &:crypto.strong_rand_bytes/1)
    codes = for _ <- 1..10, do: entropy.(12) |> Base.encode16(case: :lower)
    rounds = Keyword.get(opts, :log_rounds, @rounds)
    hashes = Enum.map(codes, &Bcrypt.hash_pwd_salt(password(&1, opts), log_rounds: rounds))
    {:ok, codes, hashes}
  end

  def supported?(nil), do: true

  def supported?(hashes) when is_list(hashes),
    do: Enum.all?(hashes, &valid_hash?/1)

  def supported?(_), do: false

  def consume(hashes, code, opts \\ []) do
    cond do
      not supported?(hashes) ->
        {:handoff, :backup_state}

      not is_binary(code) ->
        :invalid

      true ->
        hashes = hashes || []

        case Enum.find(
               hashes,
               &(not Token.blank?(&1) and Bcrypt.verify_pass(password(code, opts), &1))
             ) do
          nil -> :invalid
          hash -> {:ok, Enum.reject(hashes, &(&1 == hash))}
        end
    end
  end

  defp valid_hash?(nil), do: true

  defp valid_hash?(hash) when is_binary(hash),
    do: Token.blank?(hash) or Regex.match?(~r/\A\$2[ab]\$\d{2}\$[.\/A-Za-z0-9]{53}\z/, hash)

  defp valid_hash?(_), do: false

  defp password(code, opts) do
    pepper = Keyword.get(opts, :pepper)
    value = if Token.blank?(pepper), do: code, else: code <> pepper
    binary_part(value, 0, min(byte_size(value), 72))
  end
end
