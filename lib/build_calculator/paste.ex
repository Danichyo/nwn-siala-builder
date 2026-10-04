defmodule BuildCalculator.Paste do
  @moduledoc """
  A pasted text as a reader takes it: UTF-8, and no more than a ceiling of
  bytes — and what was done to get there, as notes.

  One copy for both readers of pasted text: the text import
  (`BuildCalculatorWeb.Builder.Import.Scan.paste/1`, task 4.34, ceiling 64 000
  bytes) and the shard's `.билд` chat log (`BuildCalculator.GameLog.parse/2`,
  task 4.39, its own ceiling). The same move made twice would be the «defect
  of copies» a fix reaches only one of (`HANDOFF.md`, task 4.35).

  Every pattern of a reader wants valid UTF-8, and neither reader may raise,
  whatever binary it is given: a paste is somebody else's text.

    * A byte sequence that is not UTF-8 — a file read in the wrong encoding,
      a character cut apart, a percent-encoded byte a browser never sends — is
      replaced with `�`, one for each broken sequence, and they are counted
      (`{:invalid_utf8, count}`).
    * A text over the ceiling is cut where a character begins, never inside
      one (`{:text_clipped, bytes}`): cut inside, it was not UTF-8 any more,
      and the first pattern to read it raised (task 4.34).
  """

  @type note :: {:invalid_utf8, pos_integer()} | {:text_clipped, pos_integer()}

  @doc """
  `text` repaired to UTF-8 and cut to at most `max_bytes`, and the notes that
  say what was done — `[]` for a UTF-8 text within the ceiling, which comes back
  unchanged.
  """
  @spec take(binary(), pos_integer()) :: {String.t(), [note()]}
  def take(text, max_bytes) when is_binary(text) and is_integer(max_bytes) and max_bytes > 0 do
    {text, broken} = valid_text(text)
    {body, clipped?} = clamp(text, max_bytes)

    notes =
      if(broken > 0, do: [{:invalid_utf8, broken}], else: []) ++
        if(clipped?, do: [{:text_clipped, max_bytes}], else: [])

    {body, notes}
  end

  defp valid_text(text) do
    if String.valid?(text) do
      {text, 0}
    else
      repaired = String.replace_invalid(text)
      {repaired, replacements(repaired) - replacements(text)}
    end
  end

  defp replacements(text), do: length(:binary.matches(text, "\uFFFD"))

  defp clamp(text, max_bytes) do
    if byte_size(text) > max_bytes,
      do: {binary_part(text, 0, char_start(text, max_bytes)), true},
      else: {text, false}
  end

  # The last place at or before `at` where a character begins: a byte that is
  # not a continuation byte (`10xxxxxx`). The text is valid UTF-8 here, so
  # three steps back at most.
  defp char_start(text, at) do
    if at > 0 and :binary.at(text, at) in 0x80..0xBF,
      do: char_start(text, at - 1),
      else: at
  end
end
