defmodule Dawarich.ActiveRecordEncryption.Zlib do
  @moduledoc false

  import Bitwise

  alias Dawarich.ActiveRecordEncryption.Message

  def inflate(<<cmf, flg, rest::binary>> = data) do
    cond do
      rem(cmf * 256 + flg, 31) != 0 -> data_error("incorrect header check")
      band(cmf, 0x0F) != 8 -> data_error("unknown compression method")
      cmf >>> 4 > 7 -> data_error("invalid window size")
      band(flg, 0x20) != 0 and byte_size(rest) < 4 -> buffer_error()
      band(flg, 0x20) != 0 -> Message.raised("Zlib::NeedDict", "need dictionary")
      true -> stream(data)
    end
  end

  def inflate(_data), do: buffer_error()

  defp stream(data) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z)

      case attempt(fn -> :zlib.inflate(z, data) end) do
        {:ok, clear} ->
          finish(z, IO.iodata_to_binary(clear))

        :error ->
          if checksum_only?(data), do: data_error("incorrect data check"), else: data_error(nil)
      end
    after
      :zlib.close(z)
    end
  end

  defp finish(z, clear) do
    case attempt(fn -> :zlib.inflateEnd(z) end) do
      {:ok, _} -> {:ok, clear}
      :error -> buffer_error()
    end
  end

  defp checksum_only?(<<_header::binary-size(2), body::binary>>) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)

      match?({:ok, _}, attempt(fn -> :zlib.inflate(z, body) end)) and
        match?({:ok, _}, attempt(fn -> :zlib.inflateEnd(z) end))
    after
      :zlib.close(z)
    end
  end

  defp attempt(fun) do
    {:ok, fun.()}
  rescue
    ErlangError -> :error
  end

  defp data_error(message), do: Message.raised("Zlib::DataError", message)
  defp buffer_error, do: Message.raised("Zlib::BufError", "buffer error")
end
