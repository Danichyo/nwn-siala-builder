defmodule BuildCalculator.Wiki.FeatNotes do
  @moduledoc """
  Reads the `Notes` section of a Fandom **feat** page for a class-level ban on
  taking the feat at all — the mirror image of
  `BuildCalculator.Wiki.ClassPage.unavailable_feat_targets/1`, the same fact
  read from the other side of the wiki (AGENT_QUEUE.md §1.10, «Источник 4»).

  `unavailable_feat_targets/1` reads a class's own `Unavailable feats` label,
  and that is the only place `Mix.Tasks.Wiki.Parse` reads a ban from before
  this module existed. Four pairs never show up there, because the wiki states
  them on the FEAT's own page instead, in prose, after the `{{feat}}`
  template:

      Knockdown, Improved knockdown (both, identical sentence):
        "Since monks receive this feat automatically, it cannot be selected
        when gaining a monk level (even prior to level 6)."
      Improved two-weapon fighting:
        "Since rangers receive this feat automatically, it cannot be selected
        when gaining a ranger level (even prior to receiving it
        automatically)."
      Blinding speed:
        "This feat cannot be selected when taking a level of [[Harper
        scout]]."

  Two grammatical shapes, not one, and both matter: "gaining a `<class>`
  level" is the wording for a feat the class also grants automatically (the
  first three say so in the very same sentence — the ban and the grant are
  ONE fact, not two); "taking a level of `<class>`" is Blinding speed's
  wording, and it grants nothing at all — there the ban is the whole fact, not
  a side effect of a grant `unavailable_feat_targets/1` could have reached
  some other way. A reader anchored on only one shape would have found three
  pairs out of four and reported the corpus clean.

  ## What this deliberately does not read

  A handful of OTHER feat pages contain "cannot be selected" without meaning
  any of this, checked by hand across every page that carries the phrase (not
  assumed — `git grep`-style sweep over all 299 vanilla feat pages, several
  verb phrasings, not just this one):

    * `Favored enemy` — "of the 25 standard races, only [[ooze]] cannot be
      selected" is about which RACE a favoured enemy may name, not which class
      may take the feat;
    * `Epic skill focus` — "cannot be selected as a rogue [[bonus feat]]"
      narrows a BONUS pool for one skill variant, not the general list a
      class-level ban removes a feat from entirely (AGENT_QUEUE.md §1.10 names
      this the one known place a class's bonus pool is narrower than its
      general pool — a different mechanic, not modelled here or anywhere else
      today);
    * `Deflect arrows` ("Arcane archers, assassins, and blackguards are unable
      to select this feat") and `Ambidexterity` ("Rangers are prohibited from
      selecting this feat") use different verbs still ("unable to", "prohibited
      from") and name pairs `ClassPage.unavailable_feat_targets/1` already
      finds on the CLASS side — read as independent confirmation by the
      caller, not guessed at here as a third shape.

  `Mix.Tasks.Wiki.Parse.report_feat_class_bans/2` prints every feat whose
  `Notes` section says "cannot be selected" and this module still returned
  nothing for — `mentions_cannot_be_selected?/1` is that broader net — so a
  wording change a future re-fetch introduces is seen in the run log rather
  than silently dropped.

  ## Scoped to the section titled exactly `Notes`

  On purpose, and case-insensitively (`==Notes==` and `== Notes ==` both
  occur): every one of the four sentences lives there, and scoping to it is
  what keeps `Custom content notes` — a DIFFERENT section, which 39 of the 299
  vanilla feat pages carry, with boilerplate about a *custom* class needing
  the feat in its own list («…that class will not be able to select it as a
  general feat», `Mix.Tasks.Wiki.Parse`'s `@restricted_by_class_categories`)
  — from ever being misread as a class-ban sentence. That boilerplate SENTENCE
  does not use either shape below (checked against all 39: neither regex ever
  matches inside it — the wording is "will not be able to select", not
  "cannot be selected when…"), so scoping to `Notes` costs nothing observable
  on the boilerplate itself. `Blinding speed` happens to carry the boilerplate
  too, in its OWN `Custom content notes`, but that is not what
  `forbidden_by_class/1` reads off it — its ban sentence is a different one,
  in its `Notes` section, matched on its own merits. The day a page is edited
  to move a ban sentence into a differently-named section is a day this
  module should say "cannot see it" loudly rather than misread the wrong
  paragraph.

  ## What comes back, and what does not

  A list of `{name, quote}` pairs, in the order the two shapes are tried (page
  order within one shape, `Notes` section only — no page in the corpus
  carries more than one ban sentence today, so this is not yet exercised
  either way). `name` is the class name **as the wiki names it** — the link
  *target* when it is a link (`Wikitext.link_targets/1`, exactly what
  `unavailable_feat_targets/1` and `proficiency_targets/1` both do), the bare
  word otherwise. `quote` is the full sentence it came from, lifted verbatim
  off the page (`Wikitext.sentence_with/2`) rather than retyped, wiki markup
  included, so it can be diffed against the source it was read from.

  Resolving `name` to a class id is the caller's job: a feat page alone has no
  class index to check it against, the same reason `unavailable_feat_targets/1`
  leaves ITS targets unresolved too.
  """

  alias BuildCalculator.Wiki.Wikitext

  @notes_section "notes"

  # "…it cannot be selected when gaining a monk level (even prior to
  # level 6)." / "…gaining a ranger level (even prior to receiving it
  # automatically)." — lazy so the capture stops at the FIRST " level" it can,
  # which is always the class name and never a `level 6` inside a trailing
  # parenthetical (`.` does not cross the line by default, so this cannot run
  # past the bullet it started on).
  @gaining ~r/cannot be selected when gaining an? (.+?) level\b/ui

  # "This feat cannot be selected when taking a level of [[Harper scout]]."
  # Bounded by the next `.` or newline rather than by `\b`, because the
  # capture may be a `[[link]]` — punctuation a word-boundary reading would
  # cut in the middle of.
  @taking ~r/cannot be selected when taking an? level of ([^\n.]+)/ui

  # The broader net `report_feat_class_bans/2` scans with, deliberately not
  # anchored to either shape above — see the moduledoc's "what this
  # deliberately does not read".
  @seen ~r/cannot be selected/ui

  @doc """
  The `{class name, full sentence}` pairs a feat page's `Notes` section states
  as a class-level ban.

  `[]` for the 295 (of 299) vanilla feat pages that state no such thing —
  including `Favored enemy` and `Epic skill focus`, the two that also contain
  the literal phrase "cannot be selected" but mean something else entirely
  (see moduledoc).
  """
  @spec forbidden_by_class(binary) :: [{binary, binary}]
  def forbidden_by_class(wikitext) do
    wikitext
    |> notes_bodies()
    |> Enum.flat_map(&bans/1)
    |> Enum.uniq()
  end

  @doc """
  Whether the page's `Notes` section says "cannot be selected" at all —
  matched by either shape above or not. The canary `report_feat_class_bans/2`
  uses to notice a wording `forbidden_by_class/1` does not yet read.
  """
  @spec mentions_cannot_be_selected?(binary) :: boolean
  def mentions_cannot_be_selected?(wikitext) do
    wikitext |> notes_bodies() |> Enum.any?(&(&1 =~ @seen))
  end

  defp notes_bodies(wikitext) do
    wikitext |> Wikitext.sections() |> Enum.filter(&notes?/1) |> Enum.map(& &1.body)
  end

  defp notes?(%{title: nil}), do: false
  defp notes?(%{title: title}), do: String.downcase(String.trim(title)) == @notes_section

  defp bans(body) do
    Enum.flat_map([@gaining, @taking], fn pattern ->
      for [whole, name] <- Regex.scan(pattern, body) do
        {class_name(name), sentence_for(body, whole)}
      end
    end)
  end

  # The link TARGET, not the display text — `[[Harper scout]]` has no pipe so
  # the two coincide today, but a future `[[Harper Scout|Harper scout]]` must
  # resolve on the target, the same rule `unavailable_feat_targets/1` and
  # `proficiency_targets/1` both already apply.
  defp class_name(raw) do
    case Wikitext.link_targets(raw) do
      [target | _] -> String.trim(target)
      [] -> raw |> Wikitext.strip_links() |> String.trim()
    end
  end

  defp sentence_for(body, anchor) do
    case Wikitext.sentence_with(body, anchor) do
      {:ok, sentence} ->
        sentence

      :error ->
        # Cannot happen on today's corpus: `anchor` is a substring of `body`,
        # just matched out of it. Raising rather than falling back to `anchor`
        # keeps a future surprise loud instead of shipping a truncated quote.
        raise ~s(the phrase "#{anchor}" that was just matched is no longer on the page)
    end
  end
end
