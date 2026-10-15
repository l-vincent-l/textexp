defmodule Textexp.Document.Search do
  @moduledoc """
  Full-text search in the documents' titles and bodies.

  The index is built in memory from the saved documents (`new_index/0`), and
  kept by its user (a LiveView) for as long as it searches; it is freed along
  with it. It does not follow later changes to the documents. It stores the
  text of the bodies, to cut the snippets of the results from them.
  """
  alias Textexp.Document
  alias Textexp.Document.Snippet
  alias TantivyEx.{Index, IndexWriter, Query, Schema, Searcher}

  # The minimum tantivy accepts for one indexing thread; the default is 50 MB.
  @writer_memory_budget 15_000_000
  @limit 20

  @doc """
  Builds the index of all the documents.
  """
  def new_index do
    documents = Document.list_documents!(load: [:text])

    with {:ok, index} <- Index.create_in_ram(schema()),
         {:ok, writer} <- IndexWriter.new(index, @writer_memory_budget),
         :ok <- add_documents(writer, documents),
         :ok <- IndexWriter.commit(writer) do
      {:ok, index}
    end
  end

  @doc """
  The documents matching `query`, best match first, with their `last_update`
  and, in their `:snippet` metadata, the fragment of their body around the
  words of the query (see `Textexp.Document.Snippet.fragment/3`), `nil` when
  only the title matches. An invalid query (e.g. `cats AND (`) matches nothing.
  """
  def search(index, query) do
    case String.trim(query) do
      "" ->
        []

      query ->
        hits = search_hits(index, query)
        bodies = Map.new(hits)
        terms = Snippet.terms(query)

        hits
        |> Enum.map(fn {id, _body} -> id end)
        |> load_documents()
        |> Enum.map(fn document ->
          snippet = Snippet.fragment(bodies[document.id], terms)
          Ash.Resource.put_metadata(document, :snippet, snippet)
        end)
    end
  end

  defp schema do
    Schema.new()
    |> Schema.add_text_field("id", :text_stored)
    |> Schema.add_text_field("title", :text)
    |> Schema.add_text_field("body", :text_stored)
  end

  defp add_documents(writer, documents) do
    Enum.reduce_while(documents, :ok, fn document, :ok ->
      fields = %{
        "id" => document.id,
        "title" => document.title || "",
        "body" => document.text
      }

      case IndexWriter.add_document(writer, fields) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # `Searcher.search/3` with a string matches every document, and
  # `Searcher.search_with_parser/6` passes the schema where the index is
  # expected: the query is parsed here.
  # The `{id, body}` of the matching documents, best match first.
  defp search_hits(index, query) do
    with {:ok, parser} <- Query.parser(index, ["title", "body"]),
         {:ok, query} <- Query.parse(parser, query),
         {:ok, searcher} <- Searcher.new(index),
         {:ok, hits} <- Searcher.search(searcher, query, @limit) do
      Enum.map(hits, &{&1["id"], &1["body"] || ""})
    else
      {:error, _reason} -> []
    end
  end

  defp load_documents([]), do: []

  defp load_documents(ids) do
    documents =
      [
        query: [filter: [id: [in: ids]], select: [:title, :excerpt, :updated_at]],
        load: [:last_update]
      ]
      |> Document.list_documents!()
      |> Map.new(&{&1.id, &1})

    # a document may have been deleted since it was indexed
    ids |> Enum.map(&documents[&1]) |> Enum.reject(&is_nil/1)
  end
end
