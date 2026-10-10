defmodule Dawarich.Uploads.Policy do
  @moduledoc false
  @gib 1024 * 1024 * 1024
  def limits(policy \\ %{}) do
    %{
      max_entries: Map.get(policy, :max_entries, env("NATIVE_UPLOAD_MAX_ENTRIES", 20)),
      max_bytes: Map.get(policy, :max_bytes, env("NATIVE_UPLOAD_MAX_BYTES", 50 * @gib)),
      aggregate_bytes:
        Map.get(policy, :aggregate_bytes, env("NATIVE_UPLOAD_AGGREGATE_BYTES", 50 * @gib)),
      ttl: Map.get(policy, :ttl, env("NATIVE_UPLOAD_TTL_SECONDS", 86_400)),
      idle_timeout: env("NATIVE_UPLOAD_IDLE_TIMEOUT_SECONDS", 120),
      preparation_bytes: env("NATIVE_UPLOAD_PREPARATION_BYTES", 64 * 1024 * 1024),
      preparation_original_bytes:
        env("NATIVE_UPLOAD_PREPARATION_ORIGINAL_BYTES", 256 * 1024 * 1024)
    }
  end

  defp env(key, default) do
    case Integer.parse(System.get_env(key, "")) do
      {value, ""} when value > 0 -> value
      _ -> default
    end
  end

  def valid?(entry, kind, limits) do
    with %{filename: name, byte_size: size, checksum: checksum, content_type: type} <- entry,
         true <- is_binary(name) and byte_size(name) in 1..255 and Path.basename(name) == name,
         true <- is_binary(type) and byte_size(type) in 1..255,
         true <- is_integer(size) and size > 0 and size <= limits.max_bytes,
         true <-
           is_integer(Map.get(entry, :original_size, size)) and
             Map.get(entry, :original_size, size) > 0,
         true <- Map.get(entry, :original_size, size) <= limits.max_bytes,
         {:ok, <<_::binary-size(16)>>} <- Base.decode64(checksum),
         true <- kind != :account or Dawarich.UserData.zip?(%{filename: name, content_type: type}) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end
end
