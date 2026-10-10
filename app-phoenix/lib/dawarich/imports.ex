defmodule Dawarich.Imports do
  @moduledoc false
  alias Dawarich.Imports.{NativeCommands, NativeReads}

  def page(scope, list, opts \\ []), do: NativeReads.page(scope, list, opts)
  def get(scope, id, opts \\ []), do: NativeReads.get(scope, id, opts)
  def create(scope, refs, opts \\ []), do: NativeCommands.create(scope, refs, opts)

  def update(scope, id, attrs, opts \\ []),
    do: NativeCommands.change(scope, id, :update, attrs, opts)

  def delete(scope, id, opts \\ []), do: NativeCommands.change(scope, id, :delete, %{}, opts)

  def extract(scope, id, attrs, opts \\ []),
    do: NativeCommands.change(scope, id, :extract, attrs, opts)

  def remove_extraction(scope, id, opts \\ []),
    do: NativeCommands.change(scope, id, :remove, %{}, opts)

  def subscribe(scope, opts \\ []), do: NativeReads.subscribe(scope, opts)
end
