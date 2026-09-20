defmodule BuildCalculatorWeb.Builder.Palette do
  @moduledoc """
  The colour of a class.

  ## Why this is a table and not a hash

  It used to be `rem(:erlang.phash2(id), 36) * 10`. That reads as principled —
  nobody hand-picks 23 numbers, a new class in the data gets a colour for free —
  and it is wrong for the one job the colour has. 23 ids into 36 buckets collide
  by the birthday problem long before they run out: Fighter and Ranger landed on
  the same hue, and so did Rogue and Sorcerer. Neighbouring buckets are 10°
  apart, which is below what the eye separates in a 3px band.

  The progression column exists so a player can see *the shape of the build* at a
  glance (CLAUDE.md §6). Two classes the same colour destroy exactly that, and no
  amount of correctness elsewhere buys it back.

  So the hues are assigned: 23 classes around the circle at ~15.6°, minimum gap
  15°, the wrap-around gap 16°, no repeats. Which class gets which is by flavour
  — martial warm, nature green, magic cold, shadows violet — because a colour
  nobody can predict is still easier to learn when it is not arbitrary.

  ## A class not in the table gets no colour at all

  `hue/1` returns `nil`, and `style/1` turns that into a desaturated grey rather
  than into hue 0. A new class in the data must look *unnamed*, not like another
  shade: silently stealing Fighter's red is the failure mode that a hash had and
  that nobody would notice for months.

  ## Prestige classes are a second ring

  Same hue, muted and lighter — `data-prc="1"` swaps `--cls-s`/`--cls-l` for
  `--prc-s`/`--prc-l` in `app.css`. That doubles how far apart two neighbouring
  hues read *and* encodes "prestige" without spending a pixel on a label. Both
  colour schemes follow, because the pairs are theme variables like everything
  else.

  ⚠️ **`data-prc` only goes on an element whose whole subtree is that one
  class**, which is why `prc/2` returns a bare `"1"` and not a class name: the
  swap is inherited, and the ability hues (`ability_hue/1` below) ride the very
  same `hsl(var(--h) var(--cls-s) var(--cls-l))` machinery. On a mixed subtree —
  a ladder row, a guide row — the row carries **`data-class-prc`** instead and
  the muting is spelled out at the one rule that wants it (`.lv-band`,
  `.v-g`). With the shared name, `▲ STR` faded on prestige levels and only
  there; measured, and the reason the two names exist.

  ⚠️ That sentence is **under test as a rule**, not as two attribute names: both
  screens assert that no `[data-prc]` element contains a descendant carrying its
  own `--h` (`builder_live_test.exs` and `build_view_live_test.exs`, «ни один
  `data-prc` не накрывает чужой оттенок»). It caught the shape of the bug twice
  and needs no browser; what it does **not** check is the resulting `rgb(...)` —
  whether the rules add up to the intended colour is only visible in a real one.
  """

  # Flavour, not decoration: warm for the martial classes, green for nature,
  # cold for arcane, violet for the shadows. Prestige classes sit next to the
  # base class they extend where there is one.
  @hues %{
    fighter: 0,
    weapon_master: 16,
    barbarian: 31,
    red_dragon_disciple: 47,
    cleric: 63,
    champion_of_torm: 78,
    paladin: 94,
    harper_scout: 110,
    ranger: 125,
    shifter: 141,
    druid: 157,
    monk: 172,
    dwarven_defender: 188,
    arcane_archer: 204,
    wizard: 219,
    pale_master: 235,
    sorcerer: 250,
    shadowdancer: 266,
    purple_dragon_knight: 282,
    rogue: 297,
    assassin: 313,
    bard: 329,
    blackguard: 344
  }

  # Каждой характеристике — свой оттенок, через ту же машинерию
  # `hsl(var(--h) var(--cls-s) var(--cls-l))`, что у классов, поэтому обе темы
  # работают сами (CLAUDE.md §6).
  #
  # Не украшение: прибавок к статам в билде максимум десять, и обычно они идут
  # в один-два стата — колонка получает **узор**, а не радугу, и сразу видно,
  # куда качали. Цвет здесь дублирует текст (`STR` написано рядом), то есть
  # подкрепляет смысл, а не несёт его в одиночку.
  @ability_hues %{str: 4, con: 30, dex: 130, int: 215, wis: 275, cha: 325}

  @doc "The assigned hue of a class, or `nil` for one the table has never heard of."
  @spec hue(atom() | nil) :: non_neg_integer() | nil
  def hue(nil), do: nil
  def hue(id) when is_atom(id), do: Map.get(@hues, id)
  def hue(_id), do: nil

  @doc "The hue of an ability score, or `nil` for anything else."
  @spec ability_hue(atom() | nil) :: non_neg_integer() | nil
  def ability_hue(nil), do: nil
  def ability_hue(id) when is_atom(id), do: Map.get(@ability_hues, id)
  def ability_hue(_id), do: nil

  @doc "Every class the table names — the guard the test suite checks the data against."
  @spec known() :: [atom()]
  def known, do: Map.keys(@hues)

  @doc """
  The `style` attribute carrying a class colour.

  An unknown class zeroes the saturation instead of picking a hue, so it renders
  grey in both themes without a second code path.
  """
  @spec style(non_neg_integer() | nil) :: String.t()
  def style(nil), do: "--h: 0; --cls-s: 0%; --prc-s: 0%"
  def style(hue), do: "--h: #{hue}"

  @doc "`\"1\"` for a prestige class, `nil` otherwise — goes straight into `data-prc`."
  @spec prc(map(), atom() | nil) :: String.t() | nil
  def prc(_ruleset, nil), do: nil

  def prc(ruleset, id) do
    case ruleset.classes do
      %{^id => %{prestige?: true}} -> "1"
      _ -> nil
    end
  end
end
