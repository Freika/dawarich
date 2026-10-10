defmodule Dawarich.Places do
  @moduledoc false
  alias Dawarich.Places.{Access, Reads, Commands}

  def list(scope, page, opts \\ []), do: read(scope, opts, &Reads.list(&1, page, &2))

  def detail(scope, raw_id, opts \\ []),
    do: member(scope, raw_id, opts, &Reads.detail/3)

  def edit(scope, raw_id, opts \\ []),
    do: member(scope, raw_id, opts, &Reads.edit/3)

  def tags(scope, opts \\ []),
    do: read(scope, opts, fn admitted, repo -> {:ok, Reads.tags(admitted, repo)} end)

  def nearby(scope, params, opts \\ []), do: Dawarich.Places.NativeNearby.run(scope, params, opts)

  def new, do: Dawarich.Places.Form.new()

  def change(scope, data) do
    with {:ok, _} <- Access.admit(scope), do: Dawarich.Places.Form.initial(data)
  end

  def change(scope, data, attrs), do: Commands.change(scope, data, attrs)
  def create(scope, attrs, opts \\ []), do: Commands.save(scope, :create, nil, attrs, opts)

  def update(scope, raw_id, attrs, opts \\ []) do
    with {:ok, id} <- parse_id(raw_id), do: Commands.save(scope, :update, id, attrs, opts)
  end

  def delete(scope, raw_id, opts \\ []) do
    with {:ok, id} <- parse_id(raw_id), do: Commands.delete(scope, id, opts)
  end

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
