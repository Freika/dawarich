defmodule Dawarich.Families.Clock do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}

  @blank ~r/\A[ \t\n\v\f\r]*\z/
  @iso ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/

  def parse(blank) when blank in [nil, false, [], %{}], do: nil

  def parse(text) when is_binary(text) do
    cond do
      text =~ @blank -> nil
      text =~ @iso -> text |> DateTime.from_iso8601() |> utc()
      true -> raise ArgumentError, "time is not ISO 8601 with an offset"
    end
  end

  def parse(_other), do: raise(ArgumentError, "time is not a string")

  def iso(nil), do: nil

  def iso(%NaiveDateTime{} = utc) do
    [[text]] = Repo.query!("SELECT " <> RailsTime.sql("$1::timestamp", 0), [utc]).rows
    text
  end

  def naive(%DateTime{} = now), do: DateTime.to_naive(now)

  defp utc({:ok, at, _offset}), do: DateTime.to_naive(at)
  defp utc(_error), do: raise(ArgumentError, "time is not a valid time")
end
