defmodule Textexp.Document.Search do
  @moduledoc """
  Full-text search in the documents' titles and bodies.

  The index is built in memory from the documents the user can read
  (`new_index/1`), and kept for as long as the user searches by a
  `Textexp.Document.SearchIndex` process (the document list page, the search
  modal). Being native memory, it is freed when that process ends. It does not follow later changes to the
  documents. It stores the text of the bodies, to cut the snippets of the
  results from them.

  Titles and bodies are analyzed as French: words are reduced to their stem
  ("statut" finds "statuts") and accents are ignored ("ecole" finds "école").
  The snippets mark the words found that way.

  The last word of a query, which may be being typed, also finds the words it
  starts ("associa" finds "association").

  The ids of the documents' tags are indexed too, so that a search can be
  limited to the documents carrying a tag before keeping the best matches.
  """
  alias Textexp.Document
  alias Textexp.Document.Snippet
  alias TantivyEx.{Index, IndexWriter, Query, Schema, Searcher, Tokenizer}

  # The minimum tantivy accepts for one indexing thread; the default is 50 MB.
  @writer_memory_budget 15_000_000
  @limit 20
  @snippet_length 200
  @tokenizer "textexp_fr"
  # Shorter, a word being typed would find too many words
  @prefix_min_length 2

  @doc """
  Builds the index of the documents `user` can read.
  """
  def new_index(user) do
    documents = Document.list_documents_with_text(user)

    with :ok <- register_tokenizer(),
         {:ok, index} <- Index.create_in_ram(schema()),
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
  An invalid query (e.g. `cats AND (`) matches nothing. With `tag_id`, only
  among the documents carrying that tag (when the index was built).
  """
  def search(index, query, user, tag_id \\ nil) do
    case String.trim(query) do
      "" ->
        []

      query ->
        case search_hits(index, query, tag_id) do
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

  # Registered globally, then given to the indexes created afterwards; again
  # for each index, which only replaces it.
  # Lowercased, stemmed as French, accents folded, words over 40 bytes dropped.
  defp register_tokenizer do
    Tokenizer.register_text_analyzer(@tokenizer, "simple", true, nil, "fr", 40, true)
  end

  defp schema do
    Schema.new()
    |> Schema.add_text_field("id", :text_stored)
    |> Schema.add_text_field_with_tokenizer("title", :text, @tokenizer)
    |> Schema.add_text_field_with_tokenizer("body", :text_stored, @tokenizer)
    # The ids of the tags, separated by spaces: one term each
    |> Schema.add_text_field_with_tokenizer("tags", :text, "whitespace")
  end

  defp add_documents(writer, documents) do
    Enum.reduce_while(documents, :ok, fn {document, text, tag_ids}, :ok ->
      fields = %{
        "id" => document.id,
        "title" => document.title || "",
        "body" => text,
        "tags" => Enum.join(tag_ids, " ")
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
  defp search_hits(index, query, tag_id) do
    with {:ok, query} <- parse_query(index, query),
         {:ok, query} <- filter_by_tag(query, tag_id),
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

  defp filter_by_tag(query, nil), do: {:ok, query}

  defp filter_by_tag(query, tag_id) do
    with {:ok, tagged} <- Query.term(schema(), "tags", tag_id) do
      Query.boolean([query, tagged], [], [])
    end
  end

  # The query, or any of the words starting with its last word.
  # Apostrophes become spaces: Tantivy reads them as quotes, so that
  # "l'association" would be a syntax error. The tokenizer splits words there
  # anyway.
  defp parse_query(index, query) do
    query = String.replace(query, "'", " ")

    with {:ok, parser} <- Query.parser(index, ["title", "body"]),
         {:ok, parsed} <- Query.parse(parser, query) do
      case prefix_queries(query) do
        [] -> {:ok, parsed}
        prefixes -> Query.boolean([], [parsed | prefixes], [])
      end
    end
  end

  # The last word, unless it is part of the query syntax (quotes, `field:`,
  # `-`...). Analyzed like the indexed
  # words, whose stems it starts ("associa" gives "associ", the stem of
  # "association"); a word whose stem is not its start is not found that way
  # ("chevau", "cheval" for "chevaux").
  defp prefix_queries(query) do
    word = query |> String.split(~r/\s/u) |> List.last()

    if String.match?(word, ~r/^[\p{L}\p{N}]+$/u) do
      schema = schema()

      for prefix <- Tokenizer.tokenize_text(@tokenizer, word),
          String.length(prefix) >= @prefix_min_length,
          field <- ["title", "body"],
          {:ok, query} <- [Query.phrase_prefix(schema, field, [prefix])] do
        query
      end
    else
      []
    end
  end

  defp load_documents([], _user), do: []

  defp load_documents(ids, user) do
    documents = user |> Document.list_documents(ids) |> Map.new(&{&1.id, &1})

    # a document may have been deleted, or made unreadable, since it was indexed
    ids |> Enum.map(&documents[&1]) |> Enum.reject(&is_nil/1)
  end
end
