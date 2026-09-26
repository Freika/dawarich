defmodule Dawarich.ReleaseMigrations.Effects.Support.Ruby do
  @moduledoc false

  import Dawarich.ReleaseMigration, only: [ruby_strip: 1]

  @decimal ~r/\A([+-]?)((?:\d+(?:_\d+)*)?)(?:\.((?:\d+(?:_\d+)*)?))?(?:[eE]([+-]?\d+(?:_\d+)*))?\z/
  @hex ~r/\A([+-]?)0[xX]((?:[0-9a-fA-F]+(?:_[0-9a-fA-F]+)*)?)(?:\.([0-9a-fA-F]*))?(?:[pP]([+-]?\d+))?\z/
  @signed_hex ~r/\A[\x09-\x0D ]*([+-])0[xX]((?:[0-9a-fA-F]+(?:_[0-9a-fA-F]+)*)?)(?:\.([0-9a-fA-F]*))?(?:[pP]([+-]?\d+))?/
  @to_f ~r/\A[\x09-\x0D ]*([+-]?)(\d+(?:_\d+)*)?(?:\.((?:\d+(?:_\d+)*)?))?(?:[eE]([+-]?\d+(?:_\d+)*))?/

  defmodule Error do
    defexception [:message]
  end

  def strip(value), do: ruby_strip(value)

  def blank?(nil), do: true
  def blank?(false), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(value) when is_map(value), do: map_size(value) == 0
  def blank?(value) when is_list(value), do: value == []
  def blank?({:object, pairs}), do: pairs == []
  def blank?(_value), do: false

  def present?(value), do: not blank?(value)

  def float(string) do
    string = strip(string)

    cond do
      match = groups(@decimal, string) -> decimal(match)
      match = groups(@hex, string) -> hex(match)
      true -> nil
    end
  end

  def to_f(string) do
    case groups(@signed_hex, string) do
      nil -> decimal(groups(@to_f, string)) || 0.0
      match -> hex(match) || 0.0
    end
  end

  def instance(nil), do: "nil"
  def instance(true), do: "true"
  def instance(false), do: "false"
  def instance(value), do: "an instance of " <> class(value)

  def index(map, key) when is_map(map), do: Map.get(map, key)

  def index({:object, pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  def index(string, key) when is_binary(string), do: if(string =~ key, do: key)

  def index(value, _key) when is_list(value) or is_integer(value),
    do: raise(Error, "no implicit conversion of String into Integer")

  def index(value, _key), do: no_method!("[]", value)

  def no_method!(name, value),
    do: raise(Error, "undefined method '#{name}' for #{instance(value)}")

  def to_s(value) when is_binary(value), do: value
  def to_s(value) when is_integer(value) or is_boolean(value), do: to_string(value)

  def to_s(value),
    do: raise(Error, "cannot reproduce Ruby's to_s of #{instance(value)}")

  def json(value) when is_binary(value), do: [?", Enum.map(String.codepoints(value), &char/1), ?"]
  def json(value) when is_map(value), do: json_object(Enum.sort(value))
  def json({:object, pairs}), do: json_object(pairs)

  def json(value) when is_list(value),
    do: [?[, Enum.intersperse(Enum.map(value, &json/1), ?,), ?]]

  def json(value) when is_float(value),
    do: raise(Error, "cannot reproduce Ruby's JSON of #{value}")

  def json(value), do: Jason.encode!(value)

  defp json_object(pairs) do
    members = Enum.map(pairs, fn {key, value} -> [json(key), ?:, json(value)] end)
    [?{, Enum.intersperse(members, ?,), ?}]
  end

  defp char(~S(")), do: ~S(\")
  defp char("\\"), do: "\\\\"
  defp char("\b"), do: "\\b"
  defp char("\f"), do: "\\f"
  defp char("\n"), do: "\\n"
  defp char("\r"), do: "\\r"
  defp char("\t"), do: "\\t"
  defp char(<<c>>) when c < 0x20, do: "\\u00" <> String.downcase(Base.encode16(<<c>>))
  defp char("<"), do: "\\u003c"
  defp char(">"), do: "\\u003e"
  defp char("&"), do: "\\u0026"
  defp char(<<0x2028::utf8>>), do: "\\u2028"
  defp char(<<0x2029::utf8>>), do: "\\u2029"
  defp char(other), do: other

  defp class(value) when is_integer(value), do: "Integer"
  defp class(value) when is_float(value), do: "Float"
  defp class(value) when is_binary(value), do: "String"
  defp class(value) when is_list(value), do: "Array"
  defp class(value) when is_map(value), do: "Hash"
  defp class({:object, _pairs}), do: "Hash"

  defp groups(regex, string) do
    case Regex.run(regex, string) do
      nil -> nil
      [_ | captured] -> captured ++ List.duplicate("", 4 - length(captured))
    end
  end

  defp decimal([sign, int, frac, exp]) when int != "" or frac != "" do
    text = digits(int, "0") <> "." <> digits(frac, "0") <> "e" <> digits(exp, "0")

    case Float.parse(text) do
      {value, ""} -> signed(sign, value)
      :error -> signed(sign, :infinity)
    end
  end

  defp decimal(_match), do: nil

  defp hex([sign, int, frac, exp]) when int != "" or frac != "" do
    mantissa = String.to_integer(digits(int, "0") <> frac, 16)
    exp = String.to_integer(digits(exp, "0")) - 4 * String.length(frac)
    signed(sign, mantissa * :math.pow(2, exp))
  rescue
    ArithmeticError -> signed(sign, :infinity)
  end

  defp hex(_match), do: nil

  defp digits("", default), do: default
  defp digits(text, _default), do: String.replace(text, "_", "")

  defp signed("-", :infinity), do: :neg_infinity
  defp signed(_sign, :infinity), do: :infinity
  defp signed("-", value), do: -value
  defp signed(_sign, value), do: value
end
