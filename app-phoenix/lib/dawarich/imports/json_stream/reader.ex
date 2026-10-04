defmodule Dawarich.Imports.JsonStream.Reader do
  @moduledoc false
  def open({:bytes, bytes}, offset, length),
    do: %{file: nil, buffer: binary_part(bytes, offset, length), remaining: length}

  def open(path, offset, length) do
    file = File.open!(path, [:read, :binary, :raw])
    {:ok, _} = :file.position(file, offset)
    %{file: file, buffer: "", remaining: length}
  end

  def close(%{file: nil}), do: :ok
  def close(r), do: File.close(r.file)
  def peek(%{buffer: <<c, _::binary>>} = r), do: {c, r}
  def peek(%{remaining: 0} = r), do: {nil, r}

  def peek(r) do
    bytes = IO.binread(r.file, min(r.remaining, 65536))
    if not is_binary(bytes), do: throw(:invalid)
    peek(%{r | buffer: bytes})
  end

  def get(r) do
    case peek(r) do
      {nil, r} ->
        {nil, r}

      {c, %{buffer: <<_, rest::binary>>} = r} ->
        {c, %{r | buffer: rest, remaining: r.remaining - 1}}
    end
  end

  def chunk(r) do
    case peek(r) do
      {nil, r} ->
        {"", r}

      {_, %{buffer: buffer} = r} ->
        size =
          case :binary.match(buffer, ["\"", "\\", <<0>>]) do
            {at, _} -> at
            :nomatch -> byte_size(buffer)
          end

        <<piece::binary-size(size), rest::binary>> = buffer
        {piece, %{r | buffer: rest, remaining: r.remaining - size}}
    end
  end

  def expect(r, byte) do
    case get(r) do
      {^byte, r} -> r
      _ -> throw(:invalid)
    end
  end

  def whitespace(r) do
    case peek(r) do
      {c, r} when c in [9, 10, 13, 32] ->
        {_c, r} = get(r)
        whitespace(r)

      {_, r} ->
        r
    end
  end

  def space(r) do
    r = whitespace(r)

    case peek(r) do
      {47, r} ->
        r = expect(r, 47)

        case get(r) do
          {42, r} -> space(block(r, nil))
          {47, r} -> space(line(r))
          _ -> throw(:invalid)
        end

      {_, r} ->
        r
    end
  end

  defp block(r, previous) do
    case get(r) do
      {nil, _} -> throw(:invalid)
      {47, r} when previous == 42 -> r
      {c, r} -> block(r, c)
    end
  end

  defp line(r) do
    case get(r) do
      {c, r} when c in [nil, 10] -> r
      {_, r} -> line(r)
    end
  end
end
