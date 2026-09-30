defmodule DawarichWeb.ExportRow do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [status_badge: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{BlobPath, HumanSize}

  @formats %{
    "json" => {"bg-primary/10 text-primary", "earth"},
    "gpx" => {"bg-success/10 text-success", "route"},
    "archive" => {"bg-warning/10 text-warning", "file-up"}
  }
  @fallback {"bg-base-200 text-base-content/50", "file-up"}

  attr :export, :map, required: true
  attr :locale, :string, required: true

  def row(assigns) do
    {css, format_icon} = Map.get(@formats, assigns.export.file_format, @fallback)

    assigns =
      assign(assigns, css: css, format_icon: format_icon, download: download(assigns.export))

    ~H"""
    <tr id={"export_#{@export.id}"} class="hover:bg-base-200/50 transition-colors">
      <td class="px-4 py-3">
        <div class="flex items-center gap-3">
          <div class={"w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 " <> @css}>
            <.icon name={@format_icon} class="w-4 h-4" />
          </div>
          <div>
            <div class="font-medium">{@export.name}</div>
            <div class="text-xs text-base-content/50">
              {@export.file_format && String.upcase(@export.file_format)} {t(
                @locale,
                "exports.table_row.middot",
                %{}
              )} {t(@locale, "enums.export.file_type." <> @export.file_type, %{})}
            </div>
          </div>
        </div>
      </td>
      <td class="px-4 py-3 text-sm tabular-nums">
        {HumanSize.format(@locale, @export.byte_size) || t(@locale, "common.not_available", %{})}
      </td>
      <td class="px-4 py-3"><.status_badge record={@export} locale={@locale} /></td>
      <td class="px-4 py-3 text-sm text-base-content/50">
        <.human_datetime locale={@locale} at={@export.created} />
      </td>
      <td class="px-4 py-3 text-right">
        <div class="flex items-center gap-1 justify-end">
          <div
            :if={@download}
            class="tooltip"
            data-tip={t(@locale, "exports.table_row.download_file", %{})}
          >
            <a href={@download} class="btn btn-ghost btn-xs" download={@export.name}><.icon
              name="arrow-big-down"
              class="w-4 h-4"
            /></a>
          </div>
          <div class="tooltip" data-tip={t(@locale, "exports.table_row.delete_export", %{})}>
            <a
              href={"/exports/#{@export.id}"}
              class="btn btn-ghost btn-xs text-error hover:bg-error/10"
              data-turbo-confirm={t(@locale, "exports.table_row.are_you_sure", %{})}
              data-turbo-method="delete"
            ><.icon name="trash-2" class="w-4 h-4" /></a>
          </div>
        </div>
      </td>
    </tr>
    """
  end

  defp download(%{status: "completed", blob_id: blob_id, filename: filename})
       when is_integer(blob_id),
       do: BlobPath.redirect_path(blob_id, filename)

  defp download(%{status: "completed", url: url}), do: if(Ruby.present?(url), do: url)
  defp download(_export), do: nil
end
