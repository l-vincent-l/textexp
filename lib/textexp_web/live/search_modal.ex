defmodule TextexpWeb.SearchModal do
  @moduledoc """
  A modal searching the documents the user can read, opened from a document's
  menu. As on the list page, the index is only built for the first search, in
  the background, and kept until the modal is closed.

  Closing (its button, a click outside, Escape) sends `close_search` to the
  LiveView, which stops rendering it.
  """
  use TextexpWeb, :live_component

  import TextexpWeb.DocumentComponents

  alias Phoenix.LiveView.AsyncResult
  alias Textexp.Document.Search

  def mount(socket) do
    {:ok,
     socket
     |> assign(form: to_form(%{"query" => ""}, as: "search"), index: nil, searched?: false)
     |> stream(:results, [])}
  end

  def render(assigns) do
    ~H"""
    <div class="modal modal-open" phx-window-keydown="close_search" phx-key="Escape">
      <section
        id="search-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="search-title"
        class="modal-box flex max-h-[80dvh] w-11/12 max-w-2xl flex-col border-2 border-base-content bg-base-100 p-5 shadow-hard sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <h2 id="search-title" class="text-sm uppercase">Rechercher</h2>
          <button
            id="search-close"
            type="button"
            phx-click="close_search"
            aria-label="Fermer"
            class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <.form
          for={@form}
          id="search-modal-form"
          phx-change="search"
          phx-submit="search"
          phx-target={@myself}
          class="mt-3"
        >
          <label class="flex items-center gap-3 border-2 border-base-content bg-base-100 px-4 py-2.5">
            <.icon name="hero-magnifying-glass" class="size-5 shrink-0 text-base-content/50" />
            <input
              id="search-modal-query"
              name={@form[:query].name}
              type="search"
              value={@form[:query].value}
              placeholder="Rechercher dans les documents"
              autocomplete="off"
              phx-debounce="300"
              phx-mounted={JS.focus()}
              phx-hook="SearchNav"
              role="combobox"
              aria-expanded="true"
              aria-autocomplete="list"
              aria-controls="search-results"
              class="grow bg-transparent text-sm outline-none placeholder:text-base-content/50"
            />
            <span
              :if={@index && @index.loading}
              id="search-modal-loading"
              class="loading loading-spinner loading-sm text-base-content/40"
              aria-label="Recherche en cours"
            ></span>
          </label>
        </.form>
        <%!-- Best match first. ↑ ↓ and Enter in the field select and open them
             (see the SearchNav hook). Its padding leaves room for the selected or
             hovered card, raised with a shadow, which it would otherwise cut. --%>
        <ul
          id="search-results"
          role="listbox"
          aria-label="Résultats"
          phx-update="stream"
          class="-mr-2 -ml-1 mt-3 flex min-h-0 flex-col gap-3 overflow-y-auto pt-1 pr-2 pb-2 pl-1"
        >
          <li
            id="search-results-empty"
            class="hidden py-6 text-center text-sm text-base-content/60 only:block"
          >
            <%= cond do %>
              <% @index && @index.failed -> %>
                La recherche n'est pas disponible
              <% @searched? -> %>
                Aucun résultat
              <% true -> %>
                Titres et contenu des documents
            <% end %>
          </li>
          <li
            :for={{id, document} <- @streams.results}
            id={id}
            role="option"
            class="[&[aria-selected=true]>a]:-translate-x-0.5 [&[aria-selected=true]>a]:-translate-y-0.5 [&[aria-selected=true]>a]:shadow-hard"
          >
            <.document_card document={document} snippet={document.snippet} />
          </li>
        </ul>
        <p class="mt-3 hidden text-xs text-base-content/60 sm:block">
          ↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer
        </p>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_search"
        aria-label="Fermer"
        tabindex="-1"
      ></button>
    </div>
    """
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = assign(socket, form: to_form(%{"query" => query}, as: "search"))

    socket =
      case socket.assigns.index do
        nil when query != "" ->
          user = socket.assigns.current_user

          socket
          |> assign(index: AsyncResult.loading())
          |> start_async(:index, fn -> Search.new_index(user) end)

        _ ->
          show_results(socket)
      end

    {:noreply, socket}
  end

  def handle_async(:index, {:ok, {:ok, index}}, socket) do
    {:noreply,
     socket
     |> assign(index: AsyncResult.ok(socket.assigns.index, index))
     |> show_results()}
  end

  def handle_async(:index, _result, socket) do
    {:noreply,
     socket
     |> assign(index: AsyncResult.failed(socket.assigns.index, :unavailable))
     |> stream(:results, [], reset: true)}
  end

  # The documents matching the query, none without query. While the index is
  # loading, the results are left as they are.
  defp show_results(socket) do
    query = String.trim(socket.assigns.form[:query].value)

    case {query, socket.assigns.index} do
      {"", _index} ->
        socket |> assign(searched?: false) |> stream(:results, [], reset: true)

      {query, %AsyncResult{ok?: true, result: index}} ->
        socket
        |> assign(searched?: true)
        |> stream(:results, Search.search(index, query, socket.assigns.current_user), reset: true)

      _loading_or_failed ->
        socket
    end
  end
end
