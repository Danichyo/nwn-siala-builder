defmodule BuildCalculatorWeb.Builder.Icons do
  @moduledoc """
  Filename → servable path for the feat/spell icon set (AGENT_QUEUE.md 3.50).

  ## Why this reads the manifest and not `ruleset.feats[id].icon` alone

  A feat's `icon` field (`Data.Loader.Feats.build_feats/1`) is the raw string
  off the Fandom template — `"Ife_alertness.gif"`, verbatim, whatever
  capitalisation and spacing the wiki editor happened to type. It is **not**
  the name of the file on disk. `mix wiki.fetch.icons` resolved each such
  string through MediaWiki's own title normalisation (capitalise the first
  character, fold spaces to underscores) before downloading, and two pairs of
  raw strings in `feats.json` collapse onto the **same** physical file that
  way (`Ife_ambidex.gif` / `ife ambidex.gif`, both `ambidexterity`'s and
  `dual_wield_feat`'s icon, are one 956-byte GIF on disk). Re-deriving that
  normalisation here would be a second implementation of a rule the manifest
  already applied once, correctly, byte-verified against what actually got
  written (`priv/rules/vanilla/icons.json`, `test/build_calculator/data/icons_test.exs`).
  So this module does not normalise anything — it looks the raw string up
  against every spelling the manifest recorded (`names`), which is exactly the
  set `icons_test.exs` proves is complete: every non-nil `icon` in
  `feats.json`/`spells.json` resolves to some manifest entry, and no entry
  names a spelling nothing asks for.

  ## Why this lives here and not in `ruleset`

  The manifest carries sha1s, declared vs. downloaded sizes, source URLs and a
  licensing note (`icons.json`'s own `_note`) — provenance for a *download*,
  not a game fact. `Rules.compute/2` has no use for any of it, so it is read
  straight off disk by the web layer instead of being threaded through
  `BuildCalculator.Data` (CLAUDE.md §5 — the core knows nothing about
  presentation). `priv/rules/vanilla/icons.json` is read whether the active
  ruleset is `vanilla` or `siala_41`: the art is Fandom's regardless of which
  rules layer is on top, exactly like the wiki text itself.

  ## 16 CSS px, not 32 — and why `image-rendering: pixelated` is not here

  Decided by Dan (AGENT_QUEUE.md 3.50, 18.08.2026), not re-litigated per call
  site: the source art is 32×32 from 2002. At 16 CSS px a 2×-density screen
  paints exactly 32 device pixels — a 1:1 blit, the only size that does that.
  32 CSS px would double it to 64 device pixels and blur; `pixelated` only
  helps when art is shown *larger* than its source, never smaller, so setting
  it here would turn an honest half-size downscale on a 1×-density screen into
  a nearest-neighbour drop of every other pixel. See `.game-icon` in
  `app.css` for where the sizing actually lives — this module only ever
  returns a path or `nil`, never a size.
  """

  @manifest "priv/rules/vanilla/icons.json"

  @external_resource @manifest
  @raw @manifest |> File.read!() |> Jason.decode!()

  # One flat map per domain, built from every spelling the manifest recorded
  # rather than from `file` alone — a raw `icon` string is looked up as
  # written, never renormalised (see moduledoc). Kept as two maps, not one,
  # even though today no raw name collides across the two: `Ife_x2epicward.gif`
  # (a spell) sits one prefix away from `Ife_ambidex.gif` (a feat), and a
  # feat/spell mix-up two years from now would be exactly the kind of thing
  # that costs nobody a test failure — the manifest already keeps the two
  # domains apart, and this module preserves that rather than flattening it.
  #
  # ⚠️ Inlined rather than factored into a local helper: a `defp` in this
  # module is not yet a callable function while these two attributes are
  # still being evaluated (`Kernel.@/1` runs each expression immediately, and
  # local function clauses are only registered once the whole module body has
  # been read) — `undefined function` at compile time, not a style choice.
  @feat_paths (for record <- @raw["feats"], name <- record["names"], into: %{} do
                 {name, "/" <> record["file"]}
               end)
  @spell_paths (for record <- @raw["spells"], name <- record["names"], into: %{} do
                  {name, "/" <> record["file"]}
                end)

  @doc """
  Servable path for a feat's icon, or `nil`.

  `nil` for two different reasons that this function does not distinguish
  (both print the same fallback glyph, CLAUDE.md §6 — see `game_icon/1`):
  the feat carries no `icon` at all (23 of them, tiered families with one
  Fandom page for the whole family), or — not observed today, guarded by
  `icons_test.exs` — the manifest has nothing under that spelling.
  """
  @spec feat_path(String.t() | nil) :: String.t() | nil
  def feat_path(nil), do: nil
  def feat_path(icon) when is_binary(icon), do: Map.get(@feat_paths, icon)

  @doc "Servable path for a spell's icon, or `nil`. Same contract as `feat_path/1`."
  @spec spell_path(String.t() | nil) :: String.t() | nil
  def spell_path(nil), do: nil
  def spell_path(icon) when is_binary(icon), do: Map.get(@spell_paths, icon)
end
