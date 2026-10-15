defmodule TextexpWeb.SearchLive do
  alias Phoenix.LiveView.AsyncResult
  use TextexpWeb, :live_view

  import TextexpWeb.DocumentComponents

  alias Textexp.Document
  alias TantivyEx.{Index, IndexWriter, Query, Schema, Searcher}

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <div id="documents-page" class="mx-auto w-full max-w-3xl px-4 py-10 sm:py-14">
        <.form
          for={@search_form}
          id="search-form"
          phx-change="search"
          phx-submit="search"
        >
          <label class="input">
            <svg class="h-[1em] opacity-50" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <g
                stroke-linejoin="round"
                stroke-linecap="round"
                stroke-width="2.5"
                fill="none"
                stroke="currentColor"
              >
                <circle cx="11" cy="11" r="8"></circle>
                <path d="m21 21-4.3-4.3"></path>
              </g>
            </svg>
            <input
              id="query"
              name="query"
              value={@search_form[:query].value}
              type="search"
              class="grow"
              placeholder="Rechercher"
              phx-debounce="300"
            />
          </label>
        </.form>
        <div :if={@index.loading}>Chargement de la recherche</div>
        <%!-- Sorted by last update, most recent first --%>
        <ul :if={@index.ok?} id="documents" class="mt-3 flex flex-col gap-3" phx-update="stream">
          <li
            id="documents-empty"
            class="hidden only:block rounded-box border border-dashed border-base-300 px-4 py-10 text-center text-sm text-base-content/60"
          >
            Aucun document
          </li>
          <li :for={{id, document} <- @streams.documents} id={id}>
            <.document_card document={document} />
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       search_form: to_form(%{"query" => ""}),
       index: AsyncResult.loading()
     )
     |> stream(:documents, [])
     |> start_async(:load_index, &load_index/0)}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(search_form: to_form(%{"query" => query})) |> search()}
  end

  # Runs the query typed while the index was loading, if any.
  def handle_async(:load_index, {:ok, {:ok, index}}, socket) do
    {:noreply,
     socket
     |> assign(:index, AsyncResult.ok(socket.assigns.index, index))
     |> search()}
  end

  def handle_async(:load_index, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, :index, AsyncResult.failed(socket.assigns.index, reason))}
  end

  def handle_async(:load_index, {:exit, reason}, socket) do
    {:noreply, assign(socket, :index, AsyncResult.failed(socket.assigns.index, {:exit, reason}))}
  end

  # `@index` is an AsyncResult: the index is in its `result` once loaded.
  defp search(%{assigns: %{index: %AsyncResult{ok?: true, result: index}}} = socket) do
    documents =
      case String.trim(socket.assigns.search_form[:query].value) do
        "" -> []
        query -> search_documents(index, query)
      end

    stream(socket, :documents, documents, reset: true)
  end

  defp search(socket), do: socket

  # The matching documents, best match first. `Searcher.search/3` with a string
  # matches every document, and `Searcher.search_with_parser/6` passes the
  # schema where the index is expected: the query is parsed here.
  defp search_documents(index, query) do
    with {:ok, parser} <- Query.parser(index, ["title", "body"]),
         {:ok, query} <- Query.parse(parser, query),
         {:ok, searcher} <- Searcher.new(index),
         {:ok, hits} <- Searcher.search(searcher, query, 20) do
      ids = Enum.map(hits, & &1["id"])

      documents =
        [query: [filter: [id: [in: ids]]], load: [:last_update]]
        |> Document.list_documents!()
        |> Map.new(&{&1.id, &1})

      # a document may have been deleted since it was indexed
      ids |> Enum.map(&documents[&1]) |> Enum.reject(&is_nil/1)
    else
      # e.g. a syntax error in the query
      {:error, _reason} -> []
    end
  end

  defp load_index() do
    documents = Document.list_documents!(load: [:last_update, :markdown])

    schema =
      Schema.new()
      |> Schema.add_text_field("title", :text_stored)
      |> Schema.add_text_field("body", :text)
      |> Schema.add_u64_field("updated_at", :fast_stored)
      |> Schema.add_text_field("id", :text_stored)

    with {:ok, index} <- Index.create_in_ram(schema),
         {:ok, writer} <- IndexWriter.new(index),
         :ok <- add_documents(writer, documents),
         :ok <- IndexWriter.commit(writer) do
      {:ok, index}
    end
  end

  defp add_documents(writer, documents) do
    Enum.reduce_while(documents, :ok, fn document, :ok ->
      case IndexWriter.add_document(writer, to_index_document(document)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp to_index_document(document) do
    %{
      "id" => document.id,
      "title" => document.title || "",
      "body" => document.markdown,
      "updated_at" => DateTime.to_unix(document.last_update)
    }
  end
end
