defmodule Dawarich.PendingImports.Intake do
  @moduledoc false
  alias Dawarich.Imports.Api
  alias Dawarich.PendingImports.Quota
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @prefix "controllers.api.v1.imports.pending."
  @origins [~r/\Ahttps:\/\/dawarich\.app\z/, ~r/\Ahttps:\/\/[a-z0-9-]+\.dawarich\.pages\.dev\z/]

  def create(repo, params, ctx) do
    with :ok <- mode(ctx),
         :ok <- origin(ctx),
         {:ok, file} <- file(params),
         :ok <- filename(params),
         :ok <- validate(file, params) do
      bytes = File.stat!(file.path).size
      key = Quota.key(ctx.now)

      case Quota.with_reservation(bytes, key, fn -> persist(repo, params, file, ctx) end) do
        {:error, :capacity} -> error(429, "storage_capacity_exceeded")
        result -> result
      end
    end
  rescue
    _ -> error(500, "an_error_occurred")
  end

  defp mode(%{self_hosted?: true}), do: {:error, 404, nil}
  defp mode(_), do: :ok

  defp origin(ctx) do
    patterns =
      if ctx.production?, do: @origins, else: [~r/\Ahttp:\/\/localhost(?::\d+)?\z/ | @origins]

    if Enum.any?(patterns, &Regex.match?(&1, ctx.origin || "")), do: :ok, else: {:error, 403, nil}
  end

  defp file(%{"file" => %Plug.Upload{} = file}), do: {:ok, file}
  defp file(_), do: error(400, "missing_file")

  defp filename(params),
    do:
      if(Ruby.blank?(params["original_filename"]), do: error(400, "missing_filename"), else: :ok)

  defp validate(file, params) do
    size = File.stat!(file.path).size

    ext =
      params["original_filename"]
      |> Dawarich.Ingest.Ruby.to_s()
      |> Path.extname()
      |> String.downcase()

    cond do
      size == 0 -> error(422, "empty_file")
      size > 100 * 1024 * 1024 -> error(413, "file_too_large")
      ext not in Api.extensions() -> error(422, "unsupported_file_type", extension: ext)
      true -> :ok
    end
  end

  defp persist(repo, params, file, ctx) do
    ticket = Ecto.UUID.generate()
    expires = DateTime.add(ctx.now, 86400)

    {:ok, blob} =
      repo.transaction(fn ->
        [[id]] =
          repo.query!(
            "INSERT INTO pending_imports(claim_ticket,original_filename,origin,source_hint,expires_at,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$6) RETURNING id",
            [
              Ecto.UUID.dump!(ticket),
              params["original_filename"],
              ctx.origin,
              Dawarich.Imports.NormalCast.Text.cast(params["source_hint"]),
              DateTime.to_naive(expires),
              DateTime.to_naive(ctx.now)
            ]
          ).rows

        Api.blob(
          repo,
          "PendingImport",
          id,
          %{file | filename: params["original_filename"]},
          ctx,
          file.content_type || "application/zip"
        )
      end)

    Api.upload(blob, file, ctx)
    Map.get(ctx, :after_commit, fn -> :ok end).()

    {:ok, 201,
     %{
       "claim_ticket" => ticket,
       "expires_at" => expiry(expires, ctx),
       "claim_url" =>
         ctx.base_url <>
           "/users/sign_up?import_ticket=" <>
           ticket <> "&utm_source=tool&utm_medium=save-to-account"
     }}
  end

  defp expiry(expires, ctx) do
    zone = Map.get(ctx, :zone, System.get_env("TIME_ZONE", "Europe/Berlin"))
    {:ok, value} = Dawarich.RailsTime.iso8601(DateTime.to_naive(expires), zone)
    value
  end

  defp error(status, key, opts \\ []), do: Api.error(status, @prefix <> key, opts)
end
