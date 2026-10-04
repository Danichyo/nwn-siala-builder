defmodule BuildCalculatorWeb.Builder.WikiBlocksTest do
  @moduledoc """
  `WikiBlocks.blocks/1` — a shard page's wikitext down to the blocks the feat
  info popover draws for the eleven shard-only feats (task 4.71): paragraph,
  bulleted and numbered list, preformatted line, heading. Inline markup is
  read down to text by `Reading.strip_wiki_prose/1`; nothing from the data
  ever becomes markup or a link.
  """
  use ExUnit.Case, async: true

  alias BuildCalculatorWeb.Builder.WikiBlocks

  test "nil and blank read as nothing to show" do
    assert WikiBlocks.blocks(nil) == []
    assert WikiBlocks.blocks("") == []
    assert WikiBlocks.blocks("\n  \n\n") == []
  end

  test "a single newline inside running text is a space; an empty line ends the paragraph" do
    assert WikiBlocks.blocks("first half\nsecond half\n\nnext paragraph") == [
             %{kind: "p", text: "first half second half"},
             %{kind: "p", text: "next paragraph"}
           ]
  end

  # The proficiency pages: «Все оружие поделено на четыре группы:» and then
  # the four groups numbered — the numbering is the tiers (1, 10, 20, 30).
  test "a run of # lines is one numbered list, a run of * lines one bulleted list" do
    raw = "Groups:\n\n# one '''2-6''' ''20/х2''\n# two\n* a\n* b"

    assert WikiBlocks.blocks(raw) == [
             %{kind: "p", text: "Groups:"},
             %{kind: "ol", items: ["one 2-6 20/х2", "two"]},
             %{kind: "ul", items: ["a", "b"]}
           ]
  end

  # As on MediaWiki: an empty line between items ends the list, numbering
  # included — the next `#` starts a new list at 1.
  test "an empty line between items starts a new list, as MediaWiki does" do
    assert WikiBlocks.blocks("# x\n\n# y") == [
             %{kind: "ol", items: ["x"]},
             %{kind: "ol", items: ["y"]}
           ]
  end

  # Instinctive throw's «Общие»: the cooldown formula is an indented line
  # between two bullets — preformatted on the page, and kept as its own
  # block rather than folded into the bullet before it.
  test "an indented line is preformatted and splits the list around it" do
    raw = "*delay of:\n 27 - (лвл монка - 14) раундов\n*second\n*third"

    assert WikiBlocks.blocks(raw) == [
             %{kind: "ul", items: ["delay of:"]},
             %{kind: "pre", text: "27 - (лвл монка - 14) раундов"},
             %{kind: "ul", items: ["second", "third"]}
           ]
  end

  test "consecutive indented lines stay separate lines of one block" do
    assert WikiBlocks.blocks(" a = 1\n b = 2") == [%{kind: "pre", text: "a = 1\nb = 2"}]
  end

  test "a heading is a block of its own, and the line after it opens a new one" do
    assert WikiBlocks.blocks("== Общее ==\ntext") == [
             %{kind: "h", text: "Общее"},
             %{kind: "p", text: "text"}
           ]
  end

  test "an indent line is its own paragraph and a horizontal rule is dropped" do
    assert WikiBlocks.blocks("a\n:b\n----\nc") == [
             %{kind: "p", text: "a"},
             %{kind: "p", text: "b"},
             %{kind: "p", text: "c"}
           ]
  end

  test "links read down to their label; nothing becomes a link" do
    raw =
      "[[Бледный мастер|Бледного мастера]] and [[Воин]] and " <>
        "[http://nwn.wikia.com/wiki/Favored_enemy любимого врага]"

    assert WikiBlocks.blocks(raw) == [
             %{kind: "p", text: "Бледного мастера and Воин and любимого врага"}
           ]
  end

  # 🔴 Безопасность: ни строка из данных, ни её кусок не становится разметкой.
  # Теги вики-прозы отбрасываются, содержимое остаётся текстом (как у всех
  # цитат поп-апа, `Reading.strip_wiki_prose/1`); `[javascript:…]` на MediaWiki
  # ссылкой не является и остаётся буквальным текстом — и здесь тоже.
  test "hostile markup never survives as a tag or a link" do
    raw =
      "*<script>alert(1)</script> item\n" <>
        "<img src=x onerror=alert(2)>text [javascript:alert(3) click me]"

    blocks = WikiBlocks.blocks(raw)

    assert blocks == [
             %{kind: "ul", items: ["alert(1) item"]},
             %{kind: "p", text: "text [javascript:alert(3) click me]"}
           ]

    for block <- blocks, text <- Map.get(block, :items, [Map.get(block, :text)]) do
      refute text =~ "<"
      refute text =~ "onerror="
    end
  end

  test "struck-through history is cut, as in every other popover quote" do
    assert WikiBlocks.blocks("was <s>3</s> 5 rounds") == [%{kind: "p", text: "was 5 rounds"}]
  end
end
