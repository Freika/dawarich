defmodule Dawarich.ZoneDst do
  @moduledoc false

  @roots ~w(/usr/share/zoneinfo /usr/share/lib/zoneinfo /etc/zoneinfo)

  def pick(_zone, [{only, _offset}]), do: only

  def pick(zone, [{earliest, _offset} | _] = candidates) do
    instants = Enum.map(candidates, &elem(&1, 0))
    flags = Enum.map(candidates, fn {instant, offset} -> dst?(zone, instant, offset) end)

    if nil in flags do
      earliest
    else
      daylight = for {instant, true} <- Enum.zip(instants, flags), do: instant
      List.last(if daylight == [], do: instants, else: daylight)
    end
  end

  def dst?(zone, epoch, offset) do
    with {:ok, relative} <- Path.safe_relative(zone),
         {:ok, bytes} <- read(relative),
         {:ok, table} <- parse(bytes),
         {^offset, dst} <- period(table, epoch) do
      dst
    else
      _ -> nil
    end
  end

  defp read(relative) do
    Enum.find_value(@roots, :error, fn root ->
      case File.read(Path.join(root, relative)) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, _reason} -> nil
      end
    end)
  end

  def parse(<<"TZif", version, _::binary-size(15), counts::binary-size(24), rest::binary>>)
      when version >= ?2 do
    <<isut::32, isstd::32, leap::32, time::32, type::32, char::32>> = counts
    skip = time * 5 + type * 6 + char + leap * 8 + isstd + isut

    case rest do
      <<_::binary-size(skip), "TZif", _::binary-size(16), second::binary-size(24), body::binary>> ->
        table(second, body)

      _ ->
        :error
    end
  end

  def parse(_bytes), do: :error

  defp table(<<isut::32, isstd::32, leap::32, time::32, type::32, char::32>>, body) do
    case body do
      <<times::binary-size(time * 8), indexes::binary-size(time), types::binary-size(type * 6),
        _chars::binary-size(char), _leap::binary-size(leap * 12),
        _flags::binary-size(isstd + isut), footer::binary>> ->
        indexes = :binary.bin_to_list(indexes)

        if Enum.all?(indexes, &(&1 < type)) do
          {:ok,
           %{
             transitions: Enum.zip(for(<<at::signed-64 <- times>>, do: at), indexes),
             types:
               List.to_tuple(
                 for <<offset::signed-32, dst, _abbreviation <- types>>, do: {offset, dst == 1}
               ),
             rules: String.contains?(footer, ",")
           }}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp period(%{transitions: transitions, types: types, rules: rules}, epoch) do
    case Enum.take_while(transitions, fn {at, _type} -> at <= epoch end) do
      [] -> types |> Tuple.to_list() |> Enum.find(fn {_offset, dst} -> not dst end)
      past when rules and length(past) == length(transitions) -> nil
      past -> elem(types, past |> List.last() |> elem(1))
    end
  end
end
