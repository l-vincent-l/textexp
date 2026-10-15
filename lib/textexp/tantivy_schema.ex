defmodule Textexp.TantivySchema do
  alias TantivyEx.{Index, IndexWriter, Schema, Searcher}

  def schema() do
    Schema.new()
    |> Schema.add_text_field("title", :text_stored)
    |> Schema.add_text_field("body", :text)
    |> Schema.add_u64_field("updated_at", :fast_stored)
    |> Schema.add_text_field("id", :text_stored)
  end

  def index() do
    schema = schema()

    {:ok, index} = Index.create_in_ram(schema)
    index
  end

  def add_documents(index, documents) do
    {:ok, writer} = IndexWriter.new(index)

    Enum.each(documents, fn document ->
      :ok = IndexWriter.add_document(writer, document)
    end)

    :ok = IndexWriter.commit(writer)
    :ok
  end

  def search_documents(index, query, limit \\ 10) do
    {:ok, searcher} = Searcher.new(index)

    case Searcher.search(searcher, query, limit) do
      {:ok, results} ->
        formatted_results = Enum.map(results, &format_result/1)
        {:ok, formatted_results}

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  defp format_result(doc) do
    %{
      title: Map.get(doc, "title"),
      body: Map.get(doc, "body"),
      id: Map.get(doc, "id"),
      updated_at: Map.get(doc, "updated_at")
    }
  end
end
