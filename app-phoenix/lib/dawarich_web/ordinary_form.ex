defmodule DawarichWeb.OrdinaryForm do
  @moduledoc false
  defstruct [:id, :generation, :changeset, :confirmation, status: :idle]

  def new(host, changeset) do
    generation = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    %__MODULE__{id: host <> "-" <> generation, generation: generation, changeset: changeset}
  end

  def validate(form, changeset), do: %{form | changeset: changeset}

  def accept(%__MODULE__{generation: generation, status: :idle} = form, generation),
    do: {:ok, %{form | status: :saving}}

  def accept(_, _), do: :refused

  def finish(form, {:ok, _}), do: %{form | status: :accepted, confirmation: nil}
  def finish(form, {:partial, _, _}), do: %{form | status: :partial, confirmation: nil}

  def finish(form, {:error, %Ecto.Changeset{} = changeset}),
    do: %{form | status: :idle, changeset: changeset}

  def finish(form, {:error, reason})
      when reason in [:not_found, :unsupported, :foreign_dependents, :unavailable, :stale_session],
      do: %{form | status: :idle}

  def finish(form, {:error, _}), do: %{form | status: :uncertain, confirmation: nil}

  def confirm(%{confirmation: nil} = form, target), do: %{form | confirmation: target}
  def confirm(form, _), do: form
  def cancel(form), do: %{form | confirmation: nil}
end
