defmodule Dawarich.Imports.NormalResume do
  @moduledoc false
  alias Dawarich.Imports.{Fence, ImportState, LeaseLost}

  def driver(lease, state, context, opts \\ []) do
    if Dawarich.Standalone.enabled?() do
      cursor = ImportState.effect!(lease, fn -> receipt!(lease, state, opts) end)
      Map.merge(context, %{resume_lease: lease, resume_offset: cursor})
    else
      context
    end
  end

  def start!(lease, state, context) do
    ImportState.start!(lease, clock(context))

    if Map.get(context, :resume_offset, 0) > 0 do
      ImportState.effect!(lease, fn ->
        lease.repo.query!(
          "UPDATE imports SET raw_points=$2,doubles=$3 WHERE id=$1",
          [lease.import.id, state.import.raw_points, state.import.doubles],
          log: false
        )
      end)
    end

    :ok
  end

  def batch(context, offset, size, fun) do
    case context do
      %{resume_lease: lease} ->
        value =
          Fence.run(context, fn ->
            [[saved]] =
              lease.repo.query!(
                "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 FOR UPDATE",
                [lease.import.id],
                log: false
              ).rows

            unless saved["cursor"] == offset, do: raise(LeaseLost)
            value = fun.()

            lease.repo.query!(
              "UPDATE phoenix.import_runs SET attachment_snapshot=$2,updated_at=now() WHERE import_id=$1",
              [lease.import.id, Map.put(saved, "cursor", offset + size)],
              log: false
            )

            value
          end)

        if callback = context[:on_batch], do: callback.(offset + size)
        value

      _ ->
        fun.()
    end
  end

  def matches?(saved, state), do: saved["attachment"] == state.attachment

  def source!(lease, source, context) do
    if Map.has_key?(context, :resume_lease) do
      ImportState.effect!(lease, fn ->
        [[saved]] =
          lease.repo.query!(
            "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 FOR UPDATE",
            [lease.import.id],
            log: false
          ).rows

        unless saved["source"] == source or (is_nil(saved["source"]) and saved["cursor"] == 0),
          do: raise(LeaseLost)

        lease.repo.query!(
          "UPDATE phoenix.import_runs SET attachment_snapshot=$2 WHERE import_id=$1",
          [lease.import.id, Map.put(saved, "source", source)],
          log: false
        )
      end)
    end

    :ok
  end

  defp receipt!(lease, state, opts) do
    [[saved]] =
      lease.repo.query!(
        "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 FOR UPDATE",
        [lease.import.id],
        log: false
      ).rows

    match = Keyword.get(opts, :matches?, &matches?/2)

    case saved do
      nil ->
        saved = %{
          "attachment" => state.attachment,
          "source" => state.import.source,
          "cursor" => 0
        }

        lease.repo.query!(
          "UPDATE phoenix.import_runs SET attachment_snapshot=$2 WHERE import_id=$1",
          [lease.import.id, saved],
          log: false
        )

        0

      %{"cursor" => cursor, "source" => source} when is_integer(cursor) and cursor >= 0 ->
        unless map_size(saved) == 3 and match.(saved, state) and source == state.import.source,
          do: raise(LeaseLost)

        cursor

      _ ->
        raise LeaseLost
    end
  end

  defp clock(%{now: fun}) when is_function(fun, 0), do: fun.()
  defp clock(%{now: now}), do: now
end
