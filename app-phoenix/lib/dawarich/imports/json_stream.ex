defmodule Dawarich.Imports.JsonStream do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.{Reader, Scalar}

  defmodule Error do
    defexception message: "Invalid JSON document", reason: :syntax
  end

  def reduce(path, acc, fun, select \\ fn _ -> false end, opts \\ []) do
    opts =
      if Keyword.get(opts, :mode, :saj) == :compat do
        opts
        |> Keyword.put(:unicode, :json)
        |> Keyword.put(:allow_nan, true)
        |> Keyword.put(:strict_numbers, true)
      else
        opts
      end

    mode = Keyword.get(opts, :mode, :saj)

    opts =
      if mode in [:phone_validate, :phone_saj], do: Keyword.put(opts, :unicode, mode), else: opts

    offset = Keyword.get(opts, :offset, 0)
    length = Keyword.get(opts, :length, File.stat!(path).size - offset)
    reader = Reader.open(path, offset, length)

    state = %{
      acc: acc,
      fun: fun,
      select: select,
      total: length,
      offset: offset,
      opts: opts,
      documents: 0
    }

    try do
      {_reader, state} = documents(Reader.space(reader), state)
      state.acc
    catch
      :invalid -> raise Error
      :invalid_float -> raise Error, reason: :invalid_float, message: "Invalid float"
    after
      Reader.close(reader)
    end
  end

  defp documents(r, s) do
    case Reader.peek(r) do
      {nil, r} ->
        if Keyword.get(s.opts, :mode, :saj) == :compat and s.documents == 0, do: throw(:invalid)
        {r, s}

      {_, r} ->
        if Keyword.get(s.opts, :mode, :saj) in [:compat, :phone_saj] and s.documents > 0,
          do: throw(:invalid)

        {_value, r, s} = value(r, [], false, s)

        r =
          if Keyword.get(s.opts, :mode, :saj) in [:compat, :phone_validate, :phone_saj],
            do: Reader.whitespace(r),
            else: Reader.space(r)

        documents(r, %{s | documents: s.documents + 1})
    end
  end

  defp value(r, path, inherited, s) do
    start = at(r, s)
    {first, r} = Reader.peek(r)
    mode = s.select.(path)
    keep = inherited or mode == true or (mode == :scalar and first not in [123, 91])

    case Reader.get(r) do
      {123, r} ->
        s = event(s, {:start, :object, path, start})
        {v, r, s} = object(Reader.space(r), path, keep, [], s)
        s = event(s, {:end, :object, path, start, at(r, s)})
        value = if(keep, do: {:object, v}, else: nil)
        {value, r, event(s, {:value, path, value, start, at(r, s)})}

      {91, r} ->
        s = event(s, {:start, :array, path, start})
        {v, r, s} = array(Reader.space(r), path, keep, [], 0, s)
        s = event(s, {:end, :array, path, start, at(r, s)})
        value = if(keep, do: Enum.reverse(v), else: nil)
        {value, r, event(s, {:value, path, value, start, at(r, s)})}

      {c, r} ->
        {v, r} = Scalar.read(c, r, keep, s.opts)
        s = event(s, {:value, path, v, start, at(r, s)})
        {v, r, s}
    end
  end

  defp object(r, path, keep, acc, s) do
    case Reader.get(r) do
      {125, r} -> {Enum.reverse(acc), r, s}
      {34, r} -> member(r, path, keep, acc, s)
      _ -> throw(:invalid)
    end
  end

  defp member(r, path, keep, acc, s) do
    {key, r} =
      Scalar.string(r, if(keep, do: true, else: :key), Keyword.get(s.opts, :unicode, :saj))

    r = r |> Reader.space() |> Reader.expect(58) |> Reader.space()
    {v, r, s} = value(r, [key | path], keep, s)
    acc = if keep, do: put(acc, key, v), else: acc

    case Reader.get(Reader.space(r)) do
      {125, r} -> {Enum.reverse(acc), r, s}
      {44, r} -> member(r |> Reader.space() |> Reader.expect(34), path, keep, acc, s)
      _ -> throw(:invalid)
    end
  end

  defp array(r, path, keep, acc, index, s) do
    case Reader.peek(r) do
      {93, r} ->
        {acc, Reader.expect(r, 93), s}

      {44, r} ->
        if Keyword.get(s.opts, :mode, :saj) in [:phone_validate, :phone_saj] do
          r = Reader.expect(r, 44) |> Reader.space() |> Reader.expect(93)
          {acc, r, s}
        else
          throw(:invalid)
        end

      {_, r} ->
        array_member(r, path, keep, acc, index, s)
    end
  end

  defp array_member(r, path, keep, acc, index, s) do
    {v, r, s} = value(r, [index | path], keep, s)
    acc = if keep, do: [v | acc], else: acc

    case Reader.get(Reader.space(r)) do
      {93, r} ->
        {acc, r, s}

      {44, r} ->
        r = Reader.space(r)

        case Reader.peek(r) do
          {93, r} ->
            if Keyword.get(s.opts, :mode, :saj) in [:phone_validate, :phone_saj],
              do: {acc, Reader.expect(r, 93), s},
              else: throw(:invalid)

          {_, r} ->
            array_member(r, path, keep, acc, index + 1, s)
        end

      _ ->
        throw(:invalid)
    end
  end

  defp put(acc, key, v) do
    if Enum.any?(acc, &(elem(&1, 0) == key)),
      do: Enum.map(acc, fn {k, old} -> {k, if(k == key, do: v, else: old)} end),
      else: [{key, v} | acc]
  end

  defp event(s, event), do: %{s | acc: s.fun.(event, s.acc)}
  defp at(r, s), do: s.offset + s.total - r.remaining
end
