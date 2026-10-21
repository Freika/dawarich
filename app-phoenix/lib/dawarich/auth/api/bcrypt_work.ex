defmodule Dawarich.Auth.Api.BcryptWork do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Token

  def classify(hash) when is_binary(hash) do
    cond do
      Token.blank?(hash) -> :blank
      not Regex.match?(~r/\A\$[0-9a-z]{2}\$[0-9]{2}\$[.\/A-Za-z0-9]{53}\z/, hash) -> :invalid
      Regex.match?(~r/\A\$2[abxy]\$(0[4-9]|[12][0-9]|3[01])\$/, hash) -> :computable
      true -> :uncomputable
    end
  end

  def classify(nil), do: :blank
  def classify(_), do: :invalid

  def compare(hash, value, opts \\ []) do
    case classify(hash) do
      :computable ->
        pepper = Keyword.get(opts, :pepper)
        value = if Token.blank?(pepper), do: value, else: value <> pepper
        hash = "$2b$" <> binary_part(hash, 4, byte_size(hash) - 4)
        {:ok, Bcrypt.verify_pass(binary_part(value, 0, min(byte_size(value), 72)), hash)}

      kind when kind in [:blank, :uncomputable] ->
        {:ok, false}

      :invalid ->
        {:replay, :hash}
    end
  end
end
