defmodule Dawarich.SchemaFingerprint do
  @moduledoc false
  alias Dawarich.Repo

  def public do
    %{
      relations:
        rows("""
        SELECT c.relname, c.relkind::text, coalesce(a.attname, ''),
               coalesce(format_type(a.atttypid, a.atttypmod), ''), coalesce(a.attnotnull, false)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
        WHERE n.nspname = 'public'
        ORDER BY 1, 3
        """),
      constraints:
        rows("""
        SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid)
        FROM pg_constraint WHERE connamespace = 'public'::regnamespace
        ORDER BY 1, 2
        """),
      functions:
        rows("""
        SELECT p.proname, pg_get_function_identity_arguments(p.oid)
        FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
        ORDER BY 1, 2
        """),
      types:
        rows("""
        SELECT t.typname, t.typtype::text
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
          AND t.typcategory != 'A'
          AND NOT (
            t.typtype = 'c' AND EXISTS (
              SELECT 1 FROM pg_class c
              WHERE c.oid = t.typrelid AND c.relkind IN ('r', 'v', 'm', 'p', 'f')
            )
          )
        ORDER BY 1, 2
        """),
      triggers:
        rows("""
        SELECT c.relname, t.tgname, pg_get_triggerdef(t.oid)
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal
        ORDER BY 1, 2
        """),
      extensions: rows("SELECT extname, extversion FROM pg_extension ORDER BY 1"),
      rails_migrations: rows("SELECT count(*)::int FROM public.schema_migrations")
    }
  end

  defp rows(sql), do: Repo.query!(sql).rows
end
