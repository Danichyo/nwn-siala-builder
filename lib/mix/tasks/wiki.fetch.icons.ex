defmodule Mix.Tasks.Wiki.Fetch.Icons do
  @shortdoc "Downloads feat/spell icon images from Fandom into priv/static/icons/"

  @moduledoc """
  Downloads the icon images `mix wiki.parse` already named (the `icon` field
  of `priv/rules/vanilla/feats.json` and `spells.json`) and writes a
  provenance manifest next to the rest of the vanilla data.

      mix wiki.fetch.icons

  Task 3.50, part A (data-miner). Decision Dan, 18.08.2026: feats and spells
  only — skills and classes carry no icon on Fandom at all, so there is
  nothing to fetch for those two layers. Part B (showing the icons, 16 CSS px,
  the CC-not-applicable `/sources` block copy) belongs to `designer`; this
  task only has to get the bytes onto disk, honestly labelled.

  Reads no wikitext cache — the `icon` field is a bare file name Fandom's
  `{{feat}}`/`{{spell}}` template already carried, and it has been sitting in
  the parsed snapshot since day one. What this task adds is what a template
  parameter cannot give: **whether that name still resolves to a real file**,
  and the actual bytes.

  Writes:

    * `priv/static/icons/feats/*.gif` / `*.png` — one file per **distinct**
      wiki file the 250 unique feat `icon` strings resolve to
    * `priv/static/icons/spells/*.gif` / `*.png` / `*.jpg` — same for the 293
      unique spell `icon` strings
    * `priv/rules/vanilla/icons.json` — the manifest: source URL, resolved
      wiki title, size, sha1, dimensions and the fetch date for every file,
      keyed by every raw `icon` string that resolves onto it

  `priv/static/` is served at the site root (`Plug.Static`, configured from
  `BuildCalculatorWeb.static_paths/0` — `"icons"` was added there by this same
  change, or the files above would sit on disk and 404 for every visitor).
  Hosted, not hotlinked, on purpose (CLAUDE.md §3 "каждый факт хранит ссылку
  на источник" plus AGENT_QUEUE 3.50: a hotlink sends every player's browser to
  Fandom's CDN, breaks the moment its `?cb=<upload timestamp>` URL changes, and
  is discourteous to a wiki this project already depends on for text).

  ## Two names, one file — and why the manifest key is a list, not a string

  MediaWiki auto-capitalises only the **first** character of a title and
  treats space and underscore as interchangeable; it does not fold case
  anywhere else. Two `icon` strings that differ only that way are not two
  files, they are one file spelled two ways in our own data — and it turned
  out there are **two** such pairs among the feats, not the one AGENT_QUEUE
  3.50 named:

      Ife_ambidex.gif   (ambidexterity)      \\
                                                -> File:Ife ambidex.gif
      ife ambidex.gif   (dual_wield_feat)    /

      ife x2ddarmor.gif   (dragon_abilities)   \\
                                                  -> File:Ife x2ddarmor.gif
      ife_x2ddarmor.gif   (draconic_armor)     /

  Both confirmed live against `action=query&prop=imageinfo` (18.08.2026): 250
  unique feat `icon` strings, 0 missing, but only **248** distinct `pageid`s —
  not 249. The task's own table already disagreed with itself before this run
  (`уникальных имён` 250+293=543 vs `резолвятся` 249+293=542), and neither
  matched a plain `Api.image_info/2` probe. Spells carry no such pair: 293
  requested, 293 distinct files.

  So a manifest record's `names` is the **list** of every raw string in our
  data that resolves onto that record's file (length 1 in the ordinary case,
  2 for the two pairs above) — not a single canonical spelling picked by hand,
  which would be inventing a fact neither `ambidexterity` nor `dual_wield_feat`
  states about itself.

  ## What "idempotent" means for a set of 2005-era GIFs

  Unlike `mix wiki.parse`, there is no cache to diff against: every run talks
  to the wiki. That is fine here — these files have not moved since 2005, and
  a MediaWiki `sha1` mismatch on a re-run would be worth knowing about, not
  worth hiding behind a skip-if-present check. Idempotent means what it means
  for `mix wiki.fetch`: given an unchanged source, the **output** — every
  byte on disk and every field of the manifest — comes out identical, and a
  file that drops out of `feats.json`/`spells.json` between two runs is
  removed from disk rather than left behind as an orphan (mirrors
  `BuildCalculator.Wiki.Cache.write!/2`).

  ## The CDN does not serve what `imageinfo` describes, by default

  Discovered running this task for the first time, not read anywhere: a plain
  GET on `imageinfo`'s own `url` does not return the GIF/PNG/JPEG MediaWiki's
  database describes. It returns a **WebP transcode** — `content-type:
  image/webp` regardless of the `Accept` header sent, for every single sampled
  file, confirmed on 16 files by hand across both domains before trusting it
  as general. Fandom's CDN (`x-thumbnailer: Thumblr` in the response) rewrites
  these 2005–2011-era GIFs on the fly to save bandwidth, and the *file
  extension in the URL* does not opt out of that.

  The fix is `&format=original` appended to every download URL, confirmed
  against the same 16 files: it returns `content-type: image/gif` for a
  `.gif`, and for the **GIF** files specifically the bytes then match
  `imageinfo`'s `sha1` exactly — every one sampled. This task appends it
  unconditionally; there would be no way to tell, from `imageinfo` alone,
  which of the 541 files would silently come back as WebP without it.

  ## PNG and JPEG do not verify against `imageinfo`'s sha1 — and that is Fandom's
  ## inconsistency, not a download error

  Even with `format=original`, the PNG and JPEG icons (16 of 541: 4 feats, 6+6
  spells) come back a *different format than WebP* (correct — PNG stays PNG,
  JPEG stays JPEG, magic bytes are right) but with a **sha1 that does not
  match `imageinfo`**. For PNG the byte count matches exactly and only the
  bytes differ; for JPEG neither byte count nor sha1 matches. This is
  reproducible and stable (fetched the same file twice, got the same "wrong"
  sha1 both times) — it is not a flaky network problem.

  It traces back to Fandom's own data, not to this task: `File:Is
  x2cucrwdsoth.jpg`'s revision history (queried directly, 18.08.2026) shows
  **two consecutive revisions with the identical sha1 `e358c93…` and two
  different declared sizes, 1010 and 1804 bytes** — which is impossible if
  that field were a hash of the bytes it claims to describe. Fandom's `sha1`
  column for files this old has drifted from what it serves, most likely
  through one of the several storage-backend migrations Wikia/Fandom has been
  through since 2005–2011, and there is no request this task can make that
  recovers bytes matching the database's original number — `format=original`
  is already the least-processed representation the CDN offers.

  So verification here is **layered, and the manifest says which layer each
  file cleared** rather than asserting one pass/fail:

    1. **Magic bytes match the MIME type MediaWiki itself reported** (`GIF8[79]a`,
       the PNG signature, a JPEG SOI marker) — hard requirement, raises. This
       is what actually catches an error page or a still-transcoded response;
       every file passes it today.
    2. **The transfer was not truncated** — `BuildCalculator.Wiki.Api.download!/1`
       checks the downloaded byte count against the response's own
       `content-length` header, independent of any wiki metadata — hard
       requirement, raises.
    3. **The downloaded bytes match `imageinfo`'s `size`/`sha1`** — checked and
       recorded as `verified` per record, but **not** a hard requirement. Every
       GIF clears it; no PNG or JPEG can, through no fault of this task. Both
       the wiki's declared `size`/`sha1` and this run's actual
       `downloaded_size`/`downloaded_sha1` are kept side by side in the
       manifest, so the discrepancy is a fact on record rather than a silent
       "trust me".
  """

  use Mix.Task

  alias BuildCalculator.Wiki.Api
  alias BuildCalculator.Wiki.Json

  @wiki "fandom"
  @static_root "priv/static/icons"
  @manifest_path "priv/rules/vanilla/icons.json"

  @domains [
    %{label: "feat", plural: "feats", source: "priv/rules/vanilla/feats.json", dir: "feats"},
    %{label: "spell", plural: "spells", source: "priv/rules/vanilla/spells.json", dir: "spells"}
  ]

  # MediaWiki's own `mime` for the file decides which magic bytes we accept —
  # this is a check against a lie in the *bytes*, not a second opinion on
  # what the file is.
  @signatures %{
    "image/gif" => ["GIF87a", "GIF89a"],
    "image/png" => [<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>],
    "image/jpeg" => [<<0xFF, 0xD8, 0xFF>>]
  }

  # `~r|...|` on purpose, not `~r{...}`: the pattern's own `{2}` quantifier
  # is a literal brace pair, and Elixir's bracket-delimited sigils do not
  # nest — `~r{a{2}b}` is itself a syntax error, closing at the first `}`.
  @url_pattern ~r|/images/[0-9a-f]/[0-9a-f]{2}/([^/]+)/revision/|

  @impl Mix.Task
  def run(_args) do
    {:ok, _apps} = Application.ensure_all_started(:req)

    fetched = Date.utc_today() |> Date.to_iso8601()

    reports = Enum.map(@domains, &fetch_domain(&1, fetched))

    write_manifest(reports, fetched)

    total_files = reports |> Enum.map(& &1.file_count) |> Enum.sum()
    total_bytes = reports |> Enum.map(& &1.total_bytes) |> Enum.sum()
    total_names = reports |> Enum.map(&length(&1.names)) |> Enum.sum()

    for report <- reports do
      Mix.shell().info(
        "[#{report.plural}] #{length(report.names)} unique icon names, " <>
          "#{report.file_count} distinct files (#{length(report.names) - report.file_count} " <>
          "name collapsed by wiki normalisation), #{kb(report.total_bytes)} KB, " <>
          "#{report.verified_count}/#{report.file_count} verified byte-for-byte against " <>
          "imageinfo, #{report.without_icon} #{report.label}s with no icon at all"
      )
    end

    Mix.shell().info(
      "[icons] #{total_names} icon-name entries, #{total_files} files on disk, " <>
        "#{kb(total_bytes)} KB total -> #{@manifest_path}"
    )
  end

  defp fetch_domain(%{label: label, plural: plural, source: source, dir: dir}, fetched) do
    path = Path.join(File.cwd!(), source)
    records = path |> File.read!() |> Jason.decode!()

    with_icon = Enum.filter(records, & &1["icon"])
    without_icon = length(records) - length(with_icon)
    names = with_icon |> Enum.map(& &1["icon"]) |> Enum.uniq() |> Enum.sort()

    Mix.shell().info("[#{plural}] resolving #{length(names)} icon names…")
    info = Api.image_info(@wiki, names)

    missing = for {name, :missing} <- info, do: name

    if missing != [] do
      Mix.raise(
        "[#{plural}] #{length(missing)} icon name(s) no longer resolve on #{@wiki}, " <>
          "and nothing here is allowed to invent a substitute: #{Enum.join(Enum.sort(missing), ", ")}"
      )
    end

    groups =
      info
      |> Enum.group_by(fn {_name, found} -> found.pageid end, fn {name, found} ->
        {name, found}
      end)
      |> Enum.map(fn {_pageid, entries} ->
        aliases = entries |> Enum.map(&elem(&1, 0)) |> Enum.sort()
        {_name, found} = hd(entries)
        {aliases, found}
      end)
      |> Enum.sort_by(fn {aliases, _found} -> hd(aliases) end)

    dupes =
      groups
      |> Enum.map(fn {aliases, found} -> filename_from_url(found.url, aliases) end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)

    if dupes != [] do
      Mix.raise(
        "[#{plural}] two different wiki files would land on the same disk name — " <>
          "refusing to let one silently overwrite the other: #{inspect(dupes)}"
      )
    end

    out_dir = Path.join([File.cwd!(), @static_root, dir])
    File.mkdir_p!(out_dir)

    records =
      for {aliases, found} <- groups do
        filename = filename_from_url(found.url, aliases)
        dest = Path.join(out_dir, filename)

        # `format=original` on purpose, unconditionally: without it Fandom's
        # CDN serves a WebP transcode for every one of these files regardless
        # of the URL's own `.gif`/`.png`/`.jpg` extension — see the moduledoc
        # section "The CDN does not serve what `imageinfo` describes".
        bytes = Api.download!(found.url <> "&format=original")
        audit = check_magic!(bytes, found, aliases, dest)
        File.write!(dest, bytes)

        %{
          names: aliases,
          file: Path.join(["icons", dir, filename]),
          resolved_title: found.title,
          pageid: found.pageid,
          size: found.size,
          width: found.width,
          height: found.height,
          mime: found.mime,
          sha1: found.sha1,
          downloaded_size: audit.downloaded_size,
          downloaded_sha1: audit.downloaded_sha1,
          verified: audit.verified,
          source_url: found.url,
          wiki: @wiki,
          fetched: fetched
        }
      end

    keep = MapSet.new(records, &(&1.file |> Path.basename()))

    for existing <- File.ls!(out_dir), not MapSet.member?(keep, existing) do
      Mix.shell().info("[#{plural}] removing stale file no longer referenced: #{existing}")
      File.rm!(Path.join(out_dir, existing))
    end

    unverified = Enum.reject(records, & &1.verified)

    if unverified != [] do
      Mix.shell().info(
        "[#{plural}] #{length(unverified)} file(s) on disk do NOT match `imageinfo`'s " <>
          "size/sha1 (Fandom's own metadata for old PNG/JPEG uploads has drifted from what " <>
          "it serves — see moduledoc); recorded honestly with verified: false, not hidden: " <>
          "#{unverified |> Enum.map(&Path.basename(&1.file)) |> Enum.join(", ")}"
      )
    end

    %{
      label: label,
      plural: plural,
      names: names,
      without_icon: without_icon,
      file_count: length(records),
      total_bytes: Enum.sum(Enum.map(records, & &1.downloaded_size)),
      verified_count: length(records) - length(unverified),
      records: records
    }
  end

  defp filename_from_url(url, aliases) do
    case Regex.run(@url_pattern, url) do
      [_, name] ->
        URI.decode(name)

      nil ->
        Mix.raise(
          "[icons] URL does not match the expected Fandom CDN shape, refusing to guess a " <>
            "file name (aliases: #{Enum.join(aliases, ", ")}): #{url}"
        )
    end
  end

  # Hard gate: are these bytes actually the MIME type MediaWiki told us to
  # expect? This is what catches a still-transcoded (WebP) or error-page
  # response. Whether they also match `imageinfo`'s `size`/`sha1` is recorded,
  # not enforced here — see the moduledoc, PNG and JPEG provably cannot clear
  # that bar through any request this task can make.
  defp check_magic!(bytes, found, aliases, dest) do
    signatures = Map.get(@signatures, found.mime, [])

    unless signatures != [] and Enum.any?(signatures, &String.starts_with?(bytes, &1)) do
      label = "#{Enum.join(aliases, " / ")} -> #{Path.basename(dest)}"

      Mix.raise(
        "[icons] #{label}: downloaded bytes do not start with a #{found.mime} signature " <>
          "(got #{byte_size(bytes)} bytes starting #{inspect(binary_part(bytes, 0, min(8, byte_size(bytes))))}) " <>
          "— looks like an error page, or the CDN is still transcoding despite " <>
          "&format=original: #{found.url}"
      )
    end

    sha1 = :sha |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
    downloaded_size = byte_size(bytes)

    %{
      downloaded_size: downloaded_size,
      downloaded_sha1: sha1,
      verified: downloaded_size == found.size and sha1 == String.downcase(found.sha1)
    }
  end

  defp write_manifest(reports, fetched) do
    path = Path.join(File.cwd!(), @manifest_path)
    File.mkdir_p!(Path.dirname(path))

    body =
      {:obj,
       [
         {"_layer", "vanilla"},
         {"_generated_by", "mix wiki.fetch.icons"},
         {"_note",
          "Provenance for the icon images under priv/static/icons/. Feats and spells only " <>
            "(decision Dan, 18.08.2026, AGENT_QUEUE 3.50) — skills and classes carry no icon " <>
            "on Fandom. `names` is every raw `icon` string from feats.json/spells.json that " <>
            "resolves onto this file; it has more than one entry exactly where MediaWiki's own " <>
            "title normalisation folds two spellings in our data onto one physical file (two " <>
            "such pairs among the feats, none among the spells — see the task moduledoc). " <>
            "`size`/`sha1` are what MediaWiki's `imageinfo` declares for the file; " <>
            "`downloaded_size`/`downloaded_sha1` are what this run actually wrote to disk " <>
            "(after asking the CDN for `&format=original`, see moduledoc — without it every " <>
            "file comes back as a WebP transcode instead). `verified: true` means the two " <>
            "agree; every GIF does, no PNG or JPEG can (Fandom's own `sha1` for those old " <>
            "uploads has drifted from what the CDN serves — provably its inconsistency, not " <>
            "a download error: File:Is x2cucrwdsoth.jpg's own revision history has two " <>
            "revisions sharing one sha1 with two different declared sizes). Fetched #{fetched}. " <>
            "Legal note (these are BioWare/Beamdog game assets, not CC-BY-SA text) lives on " <>
            "/sources, not here."}
       ] ++ Enum.map(reports, &domain_json/1)}

    File.write!(path, Json.encode!(body))
  end

  defp domain_json(%{plural: plural, records: records}) do
    {plural, Enum.map(records, &record_json/1)}
  end

  defp record_json(record) do
    {:obj,
     [
       {"names", record.names},
       {"file", record.file},
       {"resolved_title", record.resolved_title},
       {"pageid", record.pageid},
       {"size", record.size},
       {"width", record.width},
       {"height", record.height},
       {"mime", record.mime},
       {"sha1", record.sha1},
       {"downloaded_size", record.downloaded_size},
       {"downloaded_sha1", record.downloaded_sha1},
       {"verified", record.verified},
       {"source_url", record.source_url},
       {"wiki", record.wiki},
       {"fetched", record.fetched}
     ]}
  end

  defp kb(bytes), do: Float.round(bytes / 1024, 1)
end
