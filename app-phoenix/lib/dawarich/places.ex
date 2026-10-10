defmodule Dawarich.Places do
  @moduledoc false
  alias Dawarich.Places.{Access, Reads}

  def list(scope, page, opts \\ []), do: read(scope, opts, &Reads.list(&1, page, &2))

  def detail(scope, raw_id, opts \\ []),
    do: member(scope, raw_id, opts, &Reads.detail/3)

  def edit(scope, raw_id, opts \\ []),
    do: member(scope, raw_id, opts, &Reads.edit/3)

  def parse_id(id) when is_integer(id) and id > 0 and id < 1_000_000_000_000_000_000,
    do: {:ok, id}

  def parse_id(id) when is_binary(id) do
    if id =~ ~r/\A[0-9]{1,18}\z/, do: parse_id(String.to_integer(id)), else: {:error, :not_found}
  end

  def parse_id(_), do: {:error, :not_found}

  defp member(scope, id, opts, fun) do
    read(scope, opts, fn admitted, repo ->
      with {:ok, id} <- parse_id(id), do: fun.(admitted, id, repo)
    end)
  end

  defp read(scope, opts, fun) do
    with {:ok, scope} <- Access.admit(scope),
         do: fun.(scope, Keyword.get(opts, :repo, Dawarich.Repo))
  rescue
    _ -> {:error, :unavailable}
  end
end
