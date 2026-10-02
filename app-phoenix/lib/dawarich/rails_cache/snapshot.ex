defmodule Dawarich.RailsCache.Snapshot do
  @moduledoc "Typed reads of the Users::Digest and fragment HTML values Rails caches."
  import Bitwise
  alias Dawarich.RailsCache.Value

  @json ~w(toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns sharing_settings)
  @dates ~w(created_at updated_at sent_at)

  def decode(%Value{tag: :user_marshal, class: "Users::Digest", value: [attrs, _ | _]}) do
    raw_patterns = attrs["travel_patterns"]
    attrs = Map.new(attrs, fn {key, value} -> {key, from_wire(key, value)} end)

    if is_binary(raw_patterns),
      do: Map.put(attrs, "_rails_json", %{"travel_patterns" => raw_patterns}),
      else: attrs
  end

  def decode(_), do: raise(ArgumentError, "Expected Users::Digest cache snapshot")

  def html(%Value{tag: :user_class, class: "ActiveSupport::SafeBuffer", value: html})
      when is_binary(html),
      do: html

  def html(html) when is_binary(html), do: html
  def html(_), do: raise(ArgumentError, "Expected String or SafeBuffer fragment")

  defp from_wire(key, value) when key in @json and is_binary(value), do: Jason.decode!(value)

  defp from_wire(key, %Value{
         tag: :user_defined,
         class: "Time",
         value: <<p::little-32, s::little-32>>
       })
       when key in @dates do
    year = (p >>> 14 &&& 0xFFFF) + 1900
    date = Date.new!(year, (p >>> 10 &&& 15) + 1, p >>> 5 &&& 31)
    time = Time.new!(p &&& 31, s >>> 26 &&& 63, s >>> 20 &&& 63, {s &&& 0xFFFFF, 6})
    NaiveDateTime.new!(date, time)
  end

  defp from_wire(_key, value), do: value
end
