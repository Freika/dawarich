defmodule Dawarich.Imports.XmlInput do
  @moduledoc false
  alias Dawarich.Imports.{XmlPreamble, XmlTokenGuard}
  @read_size 65_536

  def new(io, opts \\ []) do
    {encoding, buffer} = XmlPreamble.read(io)
    %{io: io, encoding: encoding, pending: "", buffer: buffer, guard: XmlTokenGuard.new(opts)}
  end

  def next(s) do
    {decoded, s} = take(s)
    guard = XmlTokenGuard.feed(decoded, s.guard)
    s = %{s | guard: guard}
    if Map.has_key?(s, :checkpoint), do: Process.put(s.checkpoint, s)
    {decoded, s}
  end

  defp take(%{buffer: buffer} = s) when buffer != "" do
    size = min(byte_size(buffer), @read_size)

    {binary_part(buffer, 0, size),
     %{s | buffer: binary_part(buffer, size, byte_size(buffer) - size)}}
  end

  defp take(s) do
    case IO.binread(s.io, @read_size) do
      :eof ->
        if s.pending != "", do: raise(ArgumentError, "GPX parse error: incomplete encoding")
        {"", s}

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read GPX", path: "input"

      bytes ->
        {decoded, pending} = decode(s.pending <> bytes, s.encoding)
        {decoded, %{s | pending: pending}}
    end
  end

  defp decode(bytes, encoding) do
    case :unicode.characters_to_binary(bytes, encoding, :utf8) do
      value when is_binary(value) -> {value, ""}
      {:incomplete, value, pending} -> {value, pending}
      {:error, _, _} -> raise ArgumentError, "GPX parse error: invalid encoding"
    end
  end

  def finish(rest, s) do
    buffer = tail(rest)

    case next(s) do
      {"", _} ->
        if buffer != "",
          do: raise(ArgumentError, "GPX parse error: incomplete document tail"),
          else: :ok

      {more, s} ->
        finish(buffer <> more, s)
    end
  end

  defp tail(bytes) do
    bytes = Regex.replace(~r/\A[\x09\x0A\x0D\x20]*/, bytes, "")

    cond do
      bytes == "" -> ""
      String.starts_with?(bytes, "<!--") -> markup(bytes, "-->")
      String.starts_with?(bytes, "<?") -> markup(bytes, "?>")
      bytes in ["<", "<!", "<!-"] -> bytes
      true -> raise ArgumentError, "GPX parse error: extra content after document"
    end
  end

  defp markup(bytes, ending) do
    case :binary.match(bytes, ending) do
      :nomatch ->
        bytes

      {n, size} ->
        token = binary_part(bytes, 0, n + size)

        case :xmerl_sax_parser.stream("<tail>" <> token <> "</tail>", [
               :disallow_entities,
               external_entities: :none
             ]) do
          {:ok, _, ""} -> tail(binary_part(bytes, n + size, byte_size(bytes) - n - size))
          _ -> raise ArgumentError, "GPX parse error: invalid document tail markup"
        end
    end
  end
end
