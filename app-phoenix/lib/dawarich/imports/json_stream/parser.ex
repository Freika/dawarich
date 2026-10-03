defmodule Dawarich.Imports.JsonStream.Parser do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.{Error, Reader, Scalar}
  @max_depth 10_000
  @batch 256
  @buffer {__MODULE__, :buffer}
  @link {__MODULE__, :link}

  def run(parent, ref, path, select, opts, limit) do
    Process.flag(:max_heap_size, %{
      size: div(limit, :erlang.system_info(:wordsize)),
      kill: true,
      error_logger: false,
      include_shared_binaries: true
    })

    Process.put(@link, {parent, ref, Process.monitor(parent)})
    Process.put(@buffer, {[], 0})

    try do
      parse(path, select, options(opts))
      send(parent, {ref, :done, pending()})
    catch
      kind, reason -> send(parent, {ref, :raise, pending(), kind, reason, __STACKTRACE__})
    end
  end

  defp options(opts) do
    case Keyword.get(opts, :mode, :saj) do
      :compat -> Keyword.merge(opts, unicode: :json, allow_nan: true, strict_numbers: true)
      mode when mode in [:phone_validate, :phone_saj] -> Keyword.put(opts, :unicode, mode)
      _ -> opts
    end
  end

  defp parse(path, select, opts) do
    offset = Keyword.get(opts, :offset, 0)
    length = Keyword.get(opts, :length, File.stat!(path).size - offset)
    reader = Reader.open(path, offset, length)
    mode = Keyword.get(opts, :mode, :saj)
    state = %{select: select, total: length, offset: offset, opts: opts, mode: mode, documents: 0}

    try do
      documents(Reader.space(reader), state)
    catch
      :invalid ->
        raise Error

      :invalid_float ->
        raise Error, reason: :invalid_float, message: "Invalid float"

      :depth ->
        raise Error, reason: :depth, message: "JSON nested deeper than #{@max_depth} levels"
    after
      Reader.close(reader)
    end
  end

  defp documents(r, s) do
    case Reader.peek(r) do
      {nil, _r} ->
        if s.mode == :compat and s.documents == 0, do: throw(:invalid)

      {_, r} ->
        if s.mode in [:compat, :phone_saj] and s.documents > 0, do: throw(:invalid)
        {_value, r} = value(r, [], false, 0, s)

        r =
          if s.mode in [:compat, :phone_validate, :phone_saj],
            do: Reader.whitespace(r),
            else: Reader.space(r)

        documents(r, %{s | documents: s.documents + 1})
    end
  end

  defp value(r, path, inherited, depth, s) do
    start = at(r, s)
    {first, r} = Reader.peek(r)
    mode = s.select.(path)
    keep = inherited or mode == true or (mode == :scalar and first not in [?{, ?[])

    case Reader.get(r) do
      {c, _r} when c in [?{, ?[] and depth >= @max_depth ->
        throw(:depth)

      {?{, r} ->
        emit({:start, :object, path, start})
        {members, r} = object(Reader.space(r), path, keep, depth + 1, s)
        emit({:end, :object, path, start, at(r, s)})
        finish(if(keep, do: {:object, members}), path, start, r, s)

      {?[, r} ->
        emit({:start, :array, path, start})
        {items, r} = array(Reader.space(r), path, keep, depth + 1, [], 0, s)
        emit({:end, :array, path, start, at(r, s)})
        finish(if(keep, do: Enum.reverse(items)), path, start, r, s)

      {c, r} ->
        {v, r} = Scalar.read(c, r, keep, s.opts)
        finish(v, path, start, r, s)
    end
  end

  defp finish(value, path, start, r, s) do
    emit({:value, path, value, start, at(r, s)})
    {value, r}
  end

  defp object(r, path, keep, depth, s) do
    case Reader.get(r) do
      {?}, r} -> {[], r}
      {?", r} -> member(r, path, keep, depth, {[], %{}}, s)
      _ -> throw(:invalid)
    end
  end

  defp member(r, path, keep, depth, members, s) do
    {key, r} =
      Scalar.string(r, if(keep, do: true, else: :key), Keyword.get(s.opts, :unicode, :saj))

    r = r |> Reader.space() |> Reader.expect(?:) |> Reader.space()
    {v, r} = value(r, [key | path], keep, depth, s)
    members = if keep, do: put(members, key, v), else: members

    case Reader.get(Reader.space(r)) do
      {?}, r} -> {pairs(members), r}
      {?,, r} -> member(r |> Reader.space() |> Reader.expect(?"), path, keep, depth, members, s)
      _ -> throw(:invalid)
    end
  end

  defp put({order, map}, key, v),
    do: {if(is_map_key(map, key), do: order, else: [key | order]), Map.put(map, key, v)}

  defp pairs({order, map}), do: order |> Enum.reverse() |> Enum.map(&{&1, Map.fetch!(map, &1)})

  defp array(r, path, keep, depth, acc, index, s) do
    case Reader.peek(r) do
      {?], r} ->
        {acc, Reader.expect(r, ?])}

      {?,, r} ->
        if s.mode in [:phone_validate, :phone_saj],
          do: {acc, r |> Reader.expect(?,) |> Reader.space() |> Reader.expect(?])},
          else: throw(:invalid)

      {_, r} ->
        array_member(r, path, keep, depth, acc, index, s)
    end
  end

  defp array_member(r, path, keep, depth, acc, index, s) do
    {v, r} = value(r, [index | path], keep, depth, s)
    acc = if keep, do: [v | acc], else: acc

    case Reader.get(Reader.space(r)) do
      {?], r} -> {acc, r}
      {?,, r} -> next_member(Reader.space(r), path, keep, depth, acc, index, s)
      _ -> throw(:invalid)
    end
  end

  defp next_member(r, path, keep, depth, acc, index, s) do
    case Reader.peek(r) do
      {?], r} ->
        if s.mode in [:phone_validate, :phone_saj],
          do: {acc, Reader.expect(r, ?])},
          else: throw(:invalid)

      {_, r} ->
        array_member(r, path, keep, depth, acc, index + 1, s)
    end
  end

  defp emit(event) do
    case Process.get(@buffer) do
      {events, count} when count + 1 < @batch ->
        Process.put(@buffer, {[event | events], count + 1})

      {events, _count} ->
        Process.put(@buffer, {[], 0})
        hand_over(Enum.reverse([event | events]))
    end
  end

  defp hand_over(events) do
    {parent, ref, watch} = Process.get(@link)
    send(parent, {ref, :events, events})

    receive do
      {^ref, :more} -> :ok
      {:DOWN, ^watch, :process, _pid, _reason} -> exit(:normal)
    end
  end

  defp pending do
    {events, _count} = Process.get(@buffer)
    Enum.reverse(events)
  end

  defp at(r, s), do: s.offset + s.total - r.remaining
end
