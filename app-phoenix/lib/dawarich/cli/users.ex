defmodule Dawarich.CLI.Users do
  @moduledoc false

  import Dawarich.CLI, only: [puts: 2, fail: 2]

  alias Dawarich.ReleaseMigration

  @email ~r/\A[^@\s]+@[^@\s]+\z/
  @find "SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL"
  @taken "SELECT EXISTS (SELECT 1 FROM users WHERE email = $1 AND id <> $2)"
  @activate "UPDATE users SET status = 1 WHERE deleted_at IS NULL"
  @admin "UPDATE users SET admin = true, updated_at = now() WHERE id = $1 AND admin IS DISTINCT FROM true"
  @set_email "UPDATE users SET email = $2, updated_at = now() WHERE id = $1 AND email <> $2"
  @set_password "UPDATE users SET encrypted_password = $2, updated_at = now() WHERE id = $1"
  @password_usage "usage: dawarich users password EMAIL, with the new password on standard input"

  def activate(_args, ctx) do
    if ReleaseMigration.self_hosted?(ctx.env) do
      puts(ctx, "Activating all users...")
      ctx.repo.query!(@activate, [], log: false)
      puts(ctx, "All users have been activated")
      0
    else
      puts(ctx, "This task is only available for self-hosted users")
      1
    end
  end

  def admin([email], ctx) do
    with {:ok, id} <- find(ctx, email) do
      ctx.repo.query!(@admin, [id], log: false)
      puts(ctx, "#{normalize(email)} is now an administrator")
      0
    end
  end

  def admin(_args, ctx), do: fail(ctx, "usage: dawarich users admin EMAIL")

  def email([email, new_email], ctx) do
    new_email = normalize(new_email)

    with {:ok, id} <- find(ctx, email),
         :ok <- valid_email(ctx, id, new_email) do
      ctx.repo.query!(@set_email, [id, new_email], log: false)
      puts(ctx, "#{normalize(email)} is now #{new_email}")
      0
    end
  end

  def email(_args, ctx), do: fail(ctx, "usage: dawarich users email EMAIL NEW_EMAIL")

  def password([email], ctx) do
    with {:ok, id} <- find(ctx, email),
         {:ok, password} <- read_password(ctx) do
      ctx.repo.query!(@set_password, [id, hash_password(password)], log: false)
      puts(ctx, "Password updated for #{normalize(email)}")
      0
    end
  end

  def password(_args, ctx), do: fail(ctx, @password_usage)

  def hash_password(password),
    do: Bcrypt.Base.hash_password(password, Bcrypt.Base.gen_salt(12, true))

  defp find(ctx, email) do
    case ctx.repo.query!(@find, [normalize(email)], log: false).rows do
      [[id]] -> {:ok, id}
      [] -> fail(ctx, "no user with email #{normalize(email)}")
    end
  end

  defp valid_email(ctx, id, email) do
    cond do
      email == "" -> fail(ctx, "Email can't be blank")
      not Regex.match?(@email, email) -> fail(ctx, "Email is invalid")
      taken?(ctx, id, email) -> fail(ctx, "Email has already been taken")
      true -> :ok
    end
  end

  defp taken?(ctx, id, email),
    do: ctx.repo.query!(@taken, [email, id], log: false).rows == [[true]]

  defp read_password(ctx) do
    IO.write(ctx.err, "New password: ")
    _ = :io.setopts(ctx.stdin, echo: false)
    line = IO.gets(ctx.stdin, "")
    _ = :io.setopts(ctx.stdin, echo: true)
    IO.write(ctx.err, "\n")

    case line do
      line when is_binary(line) -> checked(ctx, String.replace(line, ~r/\r?\n\z/, ""))
      _ -> fail(ctx, @password_usage)
    end
  end

  defp checked(ctx, password) do
    case length(String.codepoints(password)) do
      0 -> fail(ctx, "Password can't be blank")
      n when n < 12 -> fail(ctx, "Password is too short (minimum is 12 characters)")
      n when n > 128 -> fail(ctx, "Password is too long (maximum is 128 characters)")
      _ -> {:ok, password}
    end
  end

  defp normalize(email), do: email |> ReleaseMigration.ruby_strip() |> String.downcase()
end
