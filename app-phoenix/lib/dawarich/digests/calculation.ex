defmodule Dawarich.Digests.Calculation do
  @moduledoc false

  alias Dawarich.Digests.{CalculateMonth, CalculateYear, Context, Store}
  alias Dawarich.RubyInteger

  def monthly(repo, user_id, year, month, opts \\ []),
    do: calculate(repo, user_id, year, month, "monthly", opts)

  def yearly(repo, user_id, year, opts \\ []),
    do: calculate(repo, user_id, year, nil, "yearly", opts)

  defp calculate(repo, user_id, year, month, kind, opts) do
    repo.transaction(fn ->
      context = Context.load!(repo, user_id, opts)
      year = RubyInteger.to_i(year)
      month = if month, do: RubyInteger.to_i(month)

      attrs =
        if kind == "monthly",
          do: CalculateMonth.attributes(repo, context, year, month),
          else: CalculateYear.attributes(repo, context, year)

      if attrs do
        callback(opts, :before_store, context)
        id = Store.save!(repo, context, kind, year, month, attrs, opts)
        callback(opts, :after_store, id)
        id
      end
    end)
  rescue
    error -> failure(error, __STACKTRACE__, opts)
  catch
    kind, reason -> failure({kind, reason}, __STACKTRACE__, opts)
  end

  defp failure(error, stack, opts) do
    if Keyword.get(opts, :error_stack, false), do: {:error, error, stack}, else: {:error, error}
  end

  defp callback(opts, key, value) do
    if fun = Keyword.get(opts, key), do: fun.(value)
  end
end
