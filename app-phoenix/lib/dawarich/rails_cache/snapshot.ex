defmodule Dawarich.RailsCache.Snapshot do
  @moduledoc "Typed adapter for the actual Users::Digest and SafeBuffer cache values."
  import Bitwise
  alias Dawarich.RailsCache.Value

  @json ~w(toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns sharing_settings)
  @dates ~w(created_at updated_at sent_at)

  def decode(%Value{tag: :user_marshal, class: "Users::Digest", value: [attrs, _ | tail]}) do
    raw_patterns = attrs["travel_patterns"]
    attrs = Map.new(attrs, fn {key, value} -> {key, from_wire(key, value)} end)

    attrs =
      if is_binary(raw_patterns),
        do: Map.put(attrs, "_rails_json", %{"travel_patterns" => raw_patterns}),
        else: attrs

    if tail == [], do: attrs, else: Map.put(attrs, "_rails_associations", tail)
  end

  def decode(_), do: raise(ArgumentError, "Expected Users::Digest cache snapshot")

  def encode(attrs) do
    {tail, attrs} = Map.pop(attrs, "_rails_associations", [])
    {json, attrs} = Map.pop(attrs, "_rails_json", %{})

    raw =
      Map.new(attrs, fn {key, value} ->
        raw = json[key]

        value =
          if is_binary(raw) and Jason.decode!(raw) == value, do: raw, else: to_wire(key, value)

        {key, value}
      end)

    %Value{tag: :user_marshal, class: "Users::Digest", value: [raw, false | tail]}
  end

  def fragment(html) when is_binary(html),
    do: %Value{
      tag: :user_class,
      class: "ActiveSupport::SafeBuffer",
      value: html,
      ivars: [{{:ruby_symbol, "E"}, true}]
    }

  def html(%Value{tag: :user_class, class: "ActiveSupport::SafeBuffer", value: html})
      when is_binary(html),
      do: html

  # ActionController.write_fragment stores content.to_str; read_fragment marks
  # that scoped cache value html_safe. Explicit SafeBuffer values remain valid.
  def html(html) when is_binary(html), do: html
  def html(_), do: raise(ArgumentError, "Expected String or SafeBuffer fragment")

  defp from_wire(key, value) when key in @json and is_binary(value), do: Jason.decode!(value)

  defp from_wire(key, %Value{
         tag: :user_defined,
         class: "Time",
         value: <<p::little-32, s::little-32>>
       })
       when key in @dates do
    # Ruby's UTC Time._dump8 representation, as used by AR database attributes.
    year = (p >>> 14 &&& 0xFFFF) + 1900
    date = Date.new!(year, (p >>> 10 &&& 15) + 1, p >>> 5 &&& 31)
    time = Time.new!(p &&& 31, s >>> 26 &&& 63, s >>> 20 &&& 63, {s &&& 0xFFFFF, 6})
    NaiveDateTime.new!(date, time)
  end

  defp from_wire(_key, value), do: value

  defp to_wire(key, value) when key in @json and value != nil, do: Jason.encode!(value)

  defp to_wire(key, %DateTime{} = value) when key in @dates,
    do: to_wire(key, DateTime.to_naive(value))

  defp to_wire(key, %NaiveDateTime{} = value) when key in @dates do
    {microseconds, _} = value.microsecond

    p =
      0xC0000000 ||| (value.year - 1900) <<< 14 ||| (value.month - 1) <<< 10 ||| value.day <<< 5 |||
        value.hour

    s = value.minute <<< 26 ||| value.second <<< 20 ||| microseconds

    %Value{
      tag: :user_defined,
      class: "Time",
      value: <<p::little-32, s::little-32>>,
      ivars: [
        {{:ruby_symbol, "zone"},
         %Value{tag: :ivar, value: "UTC", ivars: [{{:ruby_symbol, "E"}, false}]}}
      ]
    }
  end

  defp to_wire("sharing_uuid", <<_::128>> = value), do: Ecto.UUID.load!(value)
  defp to_wire(_key, value), do: value
end
