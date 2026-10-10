defmodule Dawarich.Places.Commands do
  @moduledoc false
  alias Dawarich.Places.{Access, Form, Reads, WebWrite, WebDelete}

  def change(scope, data, attrs) do
    with {:ok, admitted} <- Access.admit(scope),
         :ok <- Access.settings(admitted),
         do: Form.change(data, attrs, scope.locale)
  end

  def save(original, action, id, attrs, opts) do
    repo = Keyword.get(opts, :repo, Dawarich.Repo)

    with {:ok, scope} <- Access.admit(original),
         :ok <- Access.settings(scope),
         {:ok, data} <- previous(scope, action, id, repo),
         changeset <- Form.change(data, attrs, scope.locale),
         true <- changeset.valid? do
      context = %{native_scope: original, locale: scope.locale}
      context = if opts[:now], do: Map.put(context, :now, opts[:now]), else: context
      result(WebWrite.run(repo, action, scope.user, id, attrs, context))
    else
      false ->
        with {:ok, data} <- previous(original, action, id, repo),
             do: {:error, %{Form.change(data, attrs, original.locale) | action: action}}

      error ->
        error
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def delete(original, id, opts) do
    with {:ok, scope} <- Access.admit(original),
         :ok <- Access.settings(scope) do
      repo = Keyword.get(opts, :repo, Dawarich.Repo)
      result(WebDelete.run(repo, scope.user, id, %{native_scope: original, owner_scoped: true}))
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp previous(_, :create, _, _), do: {:ok, Form.new()}
  defp previous(scope, :update, id, repo), do: Reads.edit(scope, id, repo)
  defp result({:replay, _}), do: {:error, :unsupported}

  defp result({:error, reason})
       when reason not in [:not_found, :stale_session, :foreign_dependents],
       do: {:error, :unavailable}

  defp result(result), do: result
end
