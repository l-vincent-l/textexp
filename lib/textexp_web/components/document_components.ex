defmodule TextexpWeb.DocumentComponents do
  @moduledoc """
  Components displaying documents.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TextexpWeb.Endpoint,
    router: TextexpWeb.Router,
    statics: TextexpWeb.static_paths()

  @doc """
  A document of a list, as a card linking to it: its title, last update and
  excerpt (the first lines of its body).

  The document needs its `title`, `excerpt` and `last_update`. In search
  results, `snippet` replaces the excerpt: the fragment of the body where the
  searched words appear, as `Textexp.Document.Snippet` segments.
  """
  attr :document, :map, required: true
  attr :snippet, :list, default: nil

  def document_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/documents/#{@document.id}"}
      class="group block rounded-box border border-base-300 bg-base-100 px-5 py-4 transition duration-150 ease-out hover:-translate-y-0.5 hover:border-base-content/20 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    >
      <div class="flex items-baseline justify-between gap-4">
        <h2 class={[
          "truncate text-base font-semibold",
          if(@document.title, do: "text-base-content", else: "text-base-content/40")
        ]}>
          {@document.title || "Sans titre"}
        </h2>
        <time
          datetime={DateTime.to_iso8601(@document.last_update)}
          class="shrink-0 text-xs tabular-nums text-base-content/50"
        >
          {Calendar.strftime(@document.last_update, "%d/%m/%Y %H:%M")} UTC
        </time>
      </div>
      <%!-- On one line: whitespace between the segments would show --%>
      <p
        :if={@snippet}
        class="mt-1.5 line-clamp-3 text-sm leading-relaxed text-base-content/70"
        phx-no-format
      ><%= for {kind, text} <- @snippet do %><mark :if={kind == :match} class="rounded-sm bg-warning/40 px-0.5 font-medium text-base-content">{text}</mark><span :if={kind == :text}>{text}</span><% end %></p>
      <p
        :if={!@snippet && @document.excerpt}
        class="mt-1.5 line-clamp-3 whitespace-pre-line text-sm leading-relaxed text-base-content/70"
      >
        {@document.excerpt}
      </p>
    </.link>
    """
  end
end
