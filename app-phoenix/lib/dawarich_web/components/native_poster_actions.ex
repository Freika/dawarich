defmodule DawarichWeb.NativePosterActions do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :locale, :string, required: true

  def poster_actions(assigns) do
    ~H"""
    <div class="space-y-0.5 text-xs opacity-70 [overflow-wrap:anywhere]" data-poster-summary></div>
    <div class="divider my-0 text-xs font-medium opacity-50">{p(@locale, "export_a_file")}</div>
    <div class="grid grid-cols-2 gap-2">
      <label class="form-control min-w-0">
        <span class="label-text text-xs">{p(@locale, "format")}</span>
        <select class="select select-bordered select-sm py-0" data-poster-format>
          <option value="png" selected>{p(@locale, "png")}</option>
          <option value="pdf">{p(@locale, "pdf")}</option>
        </select>
      </label>
      <label class="form-control min-w-0" data-poster-dpi-field>
        <span class="label-text text-xs">{p(@locale, "print_dpi")}</span>
        <select class="select select-bordered select-sm py-0" data-poster-dpi>
          <option value="150">150</option>
          <option value="300" selected>300</option>
        </select>
      </label>
    </div>
    <button type="button" class="btn btn-primary btn-sm h-auto w-full py-1.5" data-poster-download>
      <Icon.icon name="download" class="h-4 w-4 shrink-0" />
      {p(@locale, "download")}
    </button>
    <p class="text-xs opacity-70" role="status" data-poster-status></p>
    """
  end

  defp p(locale, key), do: t(locale, "posters.studio." <> key, %{})
end
