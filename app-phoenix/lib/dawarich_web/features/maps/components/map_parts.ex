defmodule DawarichWeb.MapParts do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.{Icon, LocalizedDate, Params}

  attr :restricted, :boolean, required: true
  attr :url, :string, required: true
  attr :locale, :string, required: true
  attr :preview, :boolean, default: true

  def pro_badge(assigns) do
    ~H"""
    <a
      :if={@restricted}
      target="_blank"
      rel="noopener noreferrer"
      class="tooltip tooltip-bottom"
      data-tip={
        t(
          @locale,
          if(@preview, do: "helpers.application.pro_preview", else: "helpers.application.pro_only"),
          %{}
        )
      }
      tabindex="0"
      href={@url}
    ><span class="badge badge-sm badge-outline gap-1"><Icon.icon name="lock" class="w-3 h-3" />{t(
      @locale,
      "helpers.application.pro_badge",
      %{}
    )}</span></a>
    """
  end

  attr :current, :atom, required: true
  attr :controller, :string, required: true
  attr :locale, :string, required: true

  def studio_switcher(assigns) do
    ~H"""
    <div
      class="join shrink-0"
      role="group"
      aria-label={t(@locale, "shared.studio_switcher.studios", %{})}
    >
      <button
        type="button"
        class={"btn btn-xs join-item gap-1 #{if @current == :poster, do: "btn-active", else: "btn-ghost"}"}
        aria-current={if @current == :poster, do: "true"}
        data-action={if @current == :poster, do: "", else: "#{@controller}#switchToPoster"}
        {switch_target(@current == :video, @controller)}
        data-testid="studio-switch-poster"
      >
        <Icon.icon name="image" class="h-3.5 w-3.5" />
        <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher.poster", %{})}</span>
      </button>
      <button
        type="button"
        class={"btn btn-xs join-item gap-1 #{if @current == :video, do: "btn-active", else: "btn-ghost"}"}
        aria-current={if @current == :video, do: "true"}
        data-action={if @current == :video, do: "", else: "#{@controller}#switchToVideo"}
        {switch_target(@current == :poster, @controller)}
        data-testid="studio-switch-video"
      >
        <Icon.icon name="video" class="h-3.5 w-3.5" />
        <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher.video", %{})}</span>
      </button>
    </div>
    """
  end

  def map_path(query) do
    case query
         |> Enum.reject(fn {_key, value} -> is_nil(value) end)
         |> Map.new()
         |> Params.to_query() do
      "" -> "/map/v2"
      encoded -> "/map/v2?" <> encoded
    end
  end

  def human_date(locale, date), do: LocalizedDate.l(locale, date, "day_month_year")

  defp switch_target(true, controller), do: [{"data-#{controller}-target", "switchButton"}]
  defp switch_target(false, _controller), do: []
end
