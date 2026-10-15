defmodule Textexp.Document.Snippet do
  @moduledoc """
  Fragment of a text around the words of a search query, these words marked,
  to show where a document matches.

  Done in Elixir until tantivy_ex exposes tantivy's `SnippetGenerator`: words
  are cut and compared as tantivy's default tokenizer does (runs of letters and
  digits, lowercased), so that the marked words are the ones the search found.
  Lengths and offsets are in bytes.
  """

  @max_length 200
  @word ~r/[\p{L}\p{N}]+/u

  @typedoc "A part of the fragment: plain text, or a word of the query."
  @type segment :: {:text | :match, String.t()}

  @doc """
  The words searched by `query`, normalized. Field prefixes (`title:`),
  operators, boosts (`^2`), and excluded words (`-word`, `NOT word`) are
  dropped.
  """
  def terms(query) do
    query
    |> String.replace(~r/(?:\bNOT\s+|(?<![\p{L}\p{N}])-)(?:"[^"]*"|\S+)/u, " ")
    |> String.replace(~r/[\p{L}\p{N}_]+:|[\^~]\d+(?:\.\d+)?/u, " ")
    |> then(&Regex.scan(@word, &1))
    |> List.flatten()
    |> Enum.reject(&(&1 in ["AND", "OR"]))
    |> MapSet.new(&normalize/1)
  end

  @doc """
  The fragment of `text`, of at most about `max_length` bytes, holding the
  most different words of `terms`, as segments; `nil` when `text` has none of
  them. It starts and ends on word boundaries, with "…" where `text` is cut,
  and line breaks become spaces.
  """
  @spec fragment(String.t(), MapSet.t(String.t()), pos_integer()) :: [segment()] | nil
  def fragment(text, terms, max_length \\ @max_length) do
    words = for [{start, length}] <- Regex.scan(@word, text, return: :index), do: {start, length}

    matches =
      for {start, length} <- words,
          term <- [normalize(binary_part(text, start, length))],
          term in terms,
          do: {start, length, term}

    case matches do
      [] ->
        nil

      matches ->
        window = best_window(matches, max_length)
        {from, to} = bounds(text, words, window, max_length)
        segments(text, from, to, matches)
    end
  end

  defp normalize(word), do: String.downcase(word)

  # The matches fitting in `max_length` bytes from one of them, that hold the
  # most different terms; the first such window when several do.
  defp best_window(matches, max_length) do
    matches
    |> Stream.unfold(fn
      [] -> nil
      [_ | rest] = tail -> {tail, rest}
    end)
    |> Enum.map(fn [{start, _, _} = first | _] = tail ->
      window =
        case Enum.take_while(tail, fn {s, l, _} -> s + l <= start + max_length end) do
          # a single word longer than max_length
          [] -> [first]
          window -> window
        end

      {window |> Enum.uniq_by(&elem(&1, 2)) |> length(), window}
    end)
    |> Enum.max_by(&elem(&1, 0))
    |> elem(1)
  end

  # The fragment's byte range: the window, with some context before it (a third
  # of the room left) and the rest after, cut at word boundaries.
  defp bounds(text, words, window, max_length) do
    {first_start, _, _} = List.first(window)
    {last_start, last_length, _} = List.last(window)
    last_end = last_start + last_length

    lead = max(div(max_length - (last_end - first_start), 3), 0)
    from = max(first_start - lead, 0)
    to = min(max(from + max_length, last_end), byte_size(text))

    # first word starting in the fragment, last word ending in it
    from =
      if from == 0,
        do: 0,
        else: Enum.find_value(words, first_start, fn {s, _} -> s >= from && s end)

    to =
      if to == byte_size(text),
        do: to,
        else:
          words
          |> Enum.filter(fn {s, l} -> s + l <= to end)
          |> Enum.map(fn {s, l} -> s + l end)
          |> Enum.max(fn -> last_end end)
          |> max(last_end)

    {from, to}
  end

  defp segments(text, from, to, matches) do
    {segments, position} =
      Enum.flat_map_reduce(matches, from, fn {start, length, _}, position ->
        if start >= position and start + length <= to do
          {[
             {:text, binary_part(text, position, start - position)},
             {:match, binary_part(text, start, length)}
           ], start + length}
        else
          {[], position}
        end
      end)

    ([{:text, if(from > 0, do: "…", else: "")} | segments] ++
       [
         {:text, binary_part(text, position, to - position)},
         {:text, if(to < byte_size(text), do: "…", else: "")}
       ])
    |> Enum.map(fn
      {:text, text} -> {:text, String.replace(text, ~r/\s+/u, " ")}
      match -> match
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      [{:text, _} | _] = texts -> [{:text, Enum.map_join(texts, &elem(&1, 1))}]
      matches -> matches
    end)
    |> Enum.reject(&(&1 == {:text, ""}))
  end
end
