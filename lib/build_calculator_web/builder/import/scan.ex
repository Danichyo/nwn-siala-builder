defmodule BuildCalculatorWeb.Builder.Import.Scan do
  @moduledoc """
  The pass over the text: the paste clamped and cut into lines, and the state
  one pass over them keeps (`empty_scan/0`). Every part that claims a line
  takes the scan and gives it back; a note about a line nobody could use goes
  in with `add/2`. A part of `BuildCalculatorWeb.Builder.Import`.
  """

  import BuildCalculatorWeb.Builder.Import.Rx, only: [sigil_RX: 2]

  alias BuildCalculator.Paste

  # A build block is a couple of kilobytes. The ceiling is here so a pasted
  # forum thread cannot ask the parser to walk a megabyte.
  @max_bytes 64_000

  # Read by `Assembly`, which says the text was clipped, and by `Issues`, whose
  # sample of that issue names the same ceiling.
  def max_bytes, do: @max_bytes

  # The paste as the reader takes it (task 4.34): UTF-8, and no more than
  # `@max_bytes` of it — and what was done to get there, as the notes the
  # result carries (`{:invalid_utf8, count}`, `{:text_clipped, bytes}`). Every
  # pattern of the reader wants valid UTF-8, and `parse/2` never raises,
  # whatever binary it is given. The work itself is `BuildCalculator.Paste`,
  # one copy with the `.билд` log's reader (task 4.39).
  def paste(text), do: Paste.take(text, @max_bytes)

  # `level_lines` and `skill_lines` are every numbered line the scan took for a
  # level or for a level's skill purchases, in the order of the text, each
  # tagged with the numbered list (`block`) it belongs to. Which list is the
  # ladder is decided once the whole text has been seen — `ladder_block/1`.
  # `ability_blocks` are the score lines that stand together; `printed` is the
  # one of them that is read (`abilities/2`). `position` counts the non-blank
  # lines, so "together" survives an empty line between two scores.
  #
  # ⚠️ The lists in `@growing` are kept newest first while the text is read and
  # put in the order of the text once, by `finish/1` (task 4.34): appending to
  # the end of a list copies it, and a paste of thirty thousand lines nobody
  # could use spent seconds on copying its own notes. While the text is read
  # they are asked only whether they are empty and, `level_lines`, for the
  # line read last — its head.
  @growing [
    :issues,
    :level_lines,
    :skill_lines,
    :totals,
    :source_skills,
    :loose_feats,
    :stated_choices,
    :stated_increases
  ]

  def empty_scan do
    %{
      section: :head,
      title: nil,
      declared: [],
      race: nil,
      race_options: nil,
      alignment: nil,
      printed: %{},
      printed_caption: nil,
      printed_any?: false,
      ability_blocks: [],
      ability_at: nil,
      letter_run: [],
      letter_at: nil,
      letter_caption: nil,
      point_buy_at: nil,
      last_line: nil,
      last_number: nil,
      paragraph_top: nil,
      paragraph_size: 0,
      lone_above: nil,
      aside: :unread,
      saves_block: nil,
      increase_head: nil,
      rolled: nil,
      stated_choices: [],
      stated_increases: [],
      position: 0,
      level_lines: [],
      level_run: nil,
      skill_lines: [],
      skill_run: nil,
      source_skills: [],
      loose_feats: [],
      totals: [],
      issues: []
    }
  end

  # ------------------------------------------------------------------- lines --

  # Quote markers, bullets and code fences are decoration a paste picks up on the
  # way here — Discord and forum quoting, not anything the format states — so
  # stripping them costs nothing and buys every second paste.
  def lines(body) do
    body
    |> String.replace(~RX/\r\n?/, "\n")
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, number} -> {number, undecorate(line)} end)
    |> Enum.reject(fn {_number, line} -> skip_line?(line) end)
  end

  # `---Save:` / `------Fort: 22` — a run of dashes as indentation (task 4.31);
  # a single one before a number stays, it may be a sign.
  defp undecorate(line) do
    line
    |> String.replace(~RX/^[\s>|•*]+/u, "")
    |> String.replace(~RX/^-{2,}\s*|^-\s+/u, "")
    |> String.trim()
  end

  defp skip_line?(line) do
    line == "" or String.starts_with?(line, "```") or Regex.match?(~RX/^[-=_*~·—–]+$/u, line)
  end

  def add(scan, issue), do: %{scan | issues: [issue | scan.issues]}

  # Several notes at once, in the order of the text.
  def add_all(scan, issues), do: %{scan | issues: Enum.reverse(issues, scan.issues)}

  # The end of the pass: every list in `@growing` in the order of the text.
  def finish(scan),
    do: Enum.reduce(@growing, scan, &Map.update!(&2, &1, fn list -> Enum.reverse(list) end))

  def untouched?(scan) do
    scan.section == :head and scan.race == nil and scan.alignment == nil and
      not scan.printed_any? and scan.totals == [] and scan.level_lines == [] and
      scan.declared == []
  end

  # Paragraphs, for `aside/2`: a blank line opens one.
  def paragraphs(scan, number, line) do
    cond do
      scan.last_number == nil or number > scan.last_number + 1 ->
        lone = if scan.paragraph_size == 1, do: scan.paragraph_top
        %{scan | paragraph_top: line, paragraph_size: 1, lone_above: lone, aside: :unread}

      true ->
        %{scan | paragraph_size: scan.paragraph_size + 1}
    end
  end
end
