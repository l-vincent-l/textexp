defmodule Textexp.Document.Search do
  @moduledoc """
  Full-text search in the documents' titles and bodies.

  The index is built in memory from the saved documents (`new_index/0`), and
  kept by its user (a LiveView) for as long as it searches; it is freed along
  with it. It does not follow later changes to the documents.
  """
  alias Textexp.Document
  alias TantivyEx.{Index, IndexWriter, Query, Schema, Searcher}

  # The minimum tantivy accepts for one indexing thread; the default is 50 MB.
  @writer_memory_budget 15_000_000
  @limit 20

  @doc """
  Builds the index of all the documents.
  """
  def new_index do
    documents = Document.list_documents!(load: [:markdown])

    with {:ok, index} <- Index.create_in_ram(schema()),
         {:ok, writer} <- IndexWriter.new(index, @writer_memory_budget),
         :ok <- add_documents(writer, documents),
         :ok <- IndexWriter.commit(writer) do
      {:ok, index}
    end
  end

  @doc """
  The documents matching `query`, best match first, with their `last_update`.
  An invalid query (e.g. `cats AND (`) matches nothing.
  """
  def search(index, query) do
    case String.trim(query) do
      "" -> []
      query -> index |> search_ids(query) |> load_documents()
    end
  end

  defp schema do
    Schema.new()
    |> Schema.add_text_field("id", :text_stored)
    |> Schema.add_text_field("title", :text)
    |> Schema.add_text_field("body", :text)
  end

  defp add_documents(writer, documents) do
    Enum.reduce_while(documents, :ok, fn document, :ok ->
      fields = %{
        "id" => document.id,
        "title" => document.title || "",
        "body" => document.markdown
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
  defp search_ids(index, query) do
    with {:ok, parser} <- Query.parser(index, ["title", "body"]),
         {:ok, query} <- Query.parse(parser, query),
         {:ok, searcher} <- Searcher.new(index),
         {:ok, hits} <- Searcher.search(searcher, query, @limit) do
      Enum.map(hits, & &1["id"])
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
