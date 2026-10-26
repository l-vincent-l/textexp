defmodule Textexp.Document.Search do
  @moduledoc """
  Full-text search in the documents' titles and bodies.

  The index is built in memory from the documents the user can read
  (`new_index/1`), and kept by its user (a LiveView) for as long as it
  searches; it is freed along with it. It does not follow later changes to the
  documents. It stores the text of the bodies, to cut the snippets of the
  results from them.
  """
  alias Textexp.Document
  alias Textexp.Document.Snippet
  alias TantivyEx.{Index, IndexWriter, Query, Schema, Searcher}

  # The minimum tantivy accepts for one indexing thread; the default is 50 MB.
  @writer_memory_budget 15_000_000
  @limit 20
  @snippet_length 200

  @doc """
  Builds the index of the documents `user` can read.
  """
  def new_index(user) do
    documents = Document.list_documents_with_text(user)

    with {:ok, index} <- Index.create_in_ram(schema()),
         {:ok, writer} <- IndexWriter.new(index, @writer_memory_budget),
         :ok <- add_documents(writer, documents),
         :ok <- IndexWriter.commit(writer) do
      {:ok, index}
    end
  end

  @doc """
  The documents matching `query`, best match first, with in their `snippet`
  the fragment of their body around the words of the query (see
  `Textexp.Document.Snippet.segments/2`), `nil` when only the title matches.
  An invalid query (e.g. `cats AND (`) matches nothing.
  """
  def search(index, query, user) do
    case String.trim(query) do
      "" ->
        []

      query ->
        case search_hits(index, query) do
          {:ok, hits, snippet} ->
            bodies = Map.new(hits)

            hits
            |> Enum.map(fn {id, _body} -> id end)
            |> load_documents(user)
            |> Enum.map(&%{&1 | snippet: snippet.(bodies[&1.id])})

          {:error, _reason} ->
            []
        end
    end
  end

  defp schema do
    Schema.new()
    |> Schema.add_text_field("id", :text_stored)
    |> Schema.add_text_field("title", :text)
    |> Schema.add_text_field("body", :text_stored)
  end

  defp add_documents(writer, documents) do
    Enum.reduce_while(documents, :ok, fn {document, text}, :ok ->
      fields = %{
        "id" => document.id,
        "title" => document.title || "",
        "body" => text
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
  # The `{id, body}` of the matching documents, best match first, and the
  # function giving the snippet segments of a body for this query.
  defp search_hits(index, query) do
    with {:ok, parser} <- Query.parser(index, ["title", "body"]),
         {:ok, query} <- Query.parse(parser, query),
         {:ok, searcher} <- Searcher.new(index),
         {:ok, hits} <- Searcher.search(searcher, query, @limit) do
      snippet = fn body ->
        case Searcher.snippet(searcher, query, "body", body, max_num_chars: @snippet_length) do
          {:ok, snippet} -> Snippet.segments(body, snippet)
          {:error, _reason} -> nil
        end
      end

      {:ok, Enum.map(hits, &{&1["id"], &1["body"] || ""}), snippet}
    end
  end

  defp load_documents([], _user), do: []

  defp load_documents(ids, user) do
    documents = user |> Document.list_documents(ids) |> Map.new(&{&1.id, &1})

    # a document may have been deleted, or made unreadable, since it was indexed
    ids |> Enum.map(&documents[&1]) |> Enum.reject(&is_nil/1)
  end
end
