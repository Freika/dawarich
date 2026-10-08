defmodule Dawarich.Tags do
  @moduledoc false

  import Ecto.Changeset, only: [cast: 3, add_error: 4]

  alias Dawarich.Accounts.Scope
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{Repo, TagPages}
  alias Dawarich.Tags.{Validation, Writes}

  @fields ~w(name icon color privacy_radius_meters)
  @types %{name: :string, icon: :string, color: :string, privacy_radius_meters: :string}
  @id ~r/\A\d{1,18}\z/

  def new_tag,
    do: %{id: nil, name: nil, icon: nil, color: nil, privacy_radius_meters: nil, demo: false}

  def list_tags(%Scope{user: user}), do: TagPages.index(user)

  def get_tag(%Scope{user: user}, raw_id) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, tag} <- TagPages.edit(user, id) do
      {:ok, tag}
    else
      _ -> {:error, :not_found}
    end
  end

  def change_tag(%Scope{} = scope, tag, params) do
    attrs = normalize(params)

    case Validation.validate(Repo, scope.user, attrs, current(tag), scope.locale) do
      %{errors: errors} -> changeset(tag, attrs, errors)
      :rails -> changeset(tag, attrs, unreadable_radius(scope))
    end
  end

  def create_tag(%Scope{} = scope, params) do
    attrs = normalize(params)

    scope.user
    |> then(&Writes.create(Repo, &1, attrs, ctx(scope)))
    |> result(scope, new_tag(), params, :insert)
  end

  def update_tag(%Scope{} = scope, %{id: id} = tag, params) do
    case parse_id(id) do
      {:ok, id} ->
        Repo
        |> Writes.update(scope.user, id, normalize(params), ctx(scope))
        |> result(scope, tag, params, :update)

      :error ->
        {:error, :not_found}
    end
  end

  def delete_tag(%Scope{} = scope, raw_id) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, %{tag: tag}} <- Writes.destroy(Repo, scope.user, id, ctx(scope)) do
      {:ok, tag}
    else
      _ -> {:error, :not_found}
    end
  end

  def normalize(params) do
    attrs = for key <- @fields, is_binary(params[key]), into: %{}, do: {key, params[key]}

    case params["privacy_enabled"] do
      "false" ->
        Map.put(attrs, "privacy_radius_meters", "")

      "true" ->
        if Ruby.blank?(attrs["privacy_radius_meters"]),
          do: Map.put(attrs, "privacy_radius_meters", "1000"),
          else: attrs

      _ ->
        attrs
    end
  end

  defp result({:ok, %{tag: tag}}, _scope, _tag, _params, _action), do: {:ok, tag}
  defp result(:not_found, _scope, _tag, _params, _action), do: {:error, :not_found}

  defp result({:invalid, %{errors: errors}}, _scope, tag, params, action),
    do: {:error, %{changeset(tag, normalize(params), errors) | action: action}}

  defp result(:rails, scope, tag, params, action) do
    case change_tag(scope, tag, params) do
      %{errors: []} -> raise "tag write failed without a validation error"
      changeset -> {:error, %{changeset | action: action}}
    end
  end

  defp changeset(tag, attrs, errors) do
    data = for key <- Map.keys(@types), into: %{}, do: {key, text(Map.get(tag, key))}

    Enum.reduce(errors, cast({data, @types}, attrs, Map.keys(@types)), fn error, acc ->
      add_error(acc, String.to_existing_atom(error["attribute"]), error["message"],
        type: error["type"]
      )
    end)
  end

  defp unreadable_radius(scope),
    do: Validation.messages([{:privacy_radius_meters, :not_a_number, %{}}], scope.locale)

  defp current(%{id: nil}), do: %{}
  defp current(tag), do: tag

  defp ctx(scope), do: %{now: DateTime.utc_now(), locale: scope.locale}

  defp parse_id(id) when is_integer(id) and id > 0 and id < 1_000_000_000_000_000_000,
    do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    if Regex.match?(@id, id) and String.to_integer(id) > 0,
      do: {:ok, String.to_integer(id)},
      else: :error
  end

  defp parse_id(_id), do: :error

  defp text(nil), do: nil
  defp text(value), do: to_string(value)
end
