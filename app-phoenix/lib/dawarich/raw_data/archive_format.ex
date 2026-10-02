defmodule Dawarich.RawData.ArchiveFormat do
  @moduledoc false

  @salt "points_raw_data_archive"

  def key(env \\ System.get_env(), secret_key_base \\ Dawarich.RailsSecret.fetch()) do
    secret = Map.get(env, "ARCHIVE_ENCRYPTION_KEY") || secret_key_base
    Dawarich.RailsMessages.key(secret, @salt, 65_536, 32)
  end

  def build(lines), do: :zlib.gzip(Enum.map(lines, &[&1, ?\n]))

  def encrypt(gzip, key, iv \\ :crypto.strong_rand_bytes(12)) do
    plaintext = Jason.encode!(Base.encode64(gzip))
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "", true)
    Enum.map_join([ciphertext, iv, tag], "--", &Base.encode64/1)
  end

  def decode(content, metadata, key) do
    if format_version(metadata) >= 2, do: decrypt(content, key), else: {:ok, content}
  end

  def lines(gzip) do
    parts = gzip |> :zlib.gunzip() |> String.split("\n")
    if List.last(parts) == "", do: Enum.drop(parts, -1), else: parts
  end

  def ids_checksum(ids), do: ids |> Enum.sort() |> Enum.join(",") |> sha256()

  def sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp decrypt(message, key) do
    with [encoded_ciphertext, encoded_iv, encoded_tag] <- String.split(message, "--"),
         {:ok, ciphertext} <- Base.decode64(encoded_ciphertext),
         {:ok, <<_::binary-size(12)>> = iv} <- Base.decode64(encoded_iv),
         {:ok, <<_::binary-size(16)>> = tag} <- Base.decode64(encoded_tag),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "", tag, false) do
      unwrap(plaintext)
    else
      _ -> {:error, :decrypt_failed}
    end
  end

  defp unwrap(<<4, 8, _::binary>>), do: {:error, :marshal_payload}

  defp unwrap(plaintext) do
    with {:ok, encoded} when is_binary(encoded) <- Jason.decode(plaintext),
         {:ok, gzip} <- Base.decode64(encoded) do
      {:ok, gzip}
    else
      _ -> {:error, :decrypt_failed}
    end
  end

  defp format_version(%{} = metadata), do: Dawarich.RubyInteger.to_i(metadata["format_version"])
  defp format_version(_metadata), do: 0
end
