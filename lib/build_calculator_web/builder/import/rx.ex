defmodule BuildCalculatorWeb.Builder.Import.Rx do
  @moduledoc """
  `~RX`: a regex compiled once per node, for the reader's own patterns (task
  4.34). A part of `BuildCalculatorWeb.Builder.Import`.

  On Erlang/OTP 28.1 and later a `~r` literal cannot keep its compiled
  pattern in the module: it is rebuilt from the exported pattern
  (`:re.import/1`) every time the expression runs. That is half of what a
  regex costs the reader — measured 0.8 µs a call against 0.4 µs — and a
  line of the paste is asked some forty of them, so a paste of thirty
  thousand short lines spent most of its second on rebuilding patterns.

  `~RX/…/u` is the same pattern, compiled by `Regex.compile!/2` the first time
  it runs and kept in `:persistent_term` under a name made of its source and
  modifiers. A key is written when its pattern first runs and then only read;
  two processes running it first at the same moment may both write it (two
  compilations are never equal terms), and the second write then costs one
  global garbage collection — once per pattern and node, not per call. The
  source is taken as it stands: like
  `~r`, it keeps every backslash (`~r` only joins lines ended with one, which
  no pattern here has). It does not interpolate: a pattern built at run time
  stays a `~r` or a `Regex.compile!/2` of its own. A broken pattern fails the
  build, as with `~r`.

  ⚠️ A module attribute is not a place for it: an attribute is evaluated
  when the module is compiled, and its regex then goes into every use as a
  `~r` would. A list of patterns is a function instead.

  🔴 **`\d` here is an ASCII digit, `0`–`9`** — every pattern is compiled
  with PCRE2's `(?aD)` in front (`ascii_digits/1`). With `u` (which turns on
  Unicode properties for `\w`, `\s`, `\d`) PCRE reads a digit of any script
  as `\d`, and the reader hands what `\d` took to `String.to_integer/1`,
  which knows only ASCII: `Fighter(٣)` raised (task 4.34). A number in a build
  is written in ASCII digits; a digit of another script is read as any other
  character, `\D` included. `\s`, `\w` and `\b` stay Unicode — a no-break
  space is a space.
  """

  defmacro sigil_RX({:<<>>, _meta, [source]}, modifiers) when is_binary(source) do
    source = ascii_digits(source)
    options = List.to_string(modifiers)
    _ = Regex.compile!(source, options)
    key = :"#{__MODULE__}.#{Base.encode16(:erlang.md5([source, 0, options]), case: :lower)}"

    quote do
      unquote(__MODULE__).fetch(unquote(key), unquote(source), unquote(options))
    end
  end

  @doc """
  The pattern with `\\d` and `\\D` read as ASCII only — for a pattern the
  reader builds at run time (`Regex.compile!/2`), so that a digit means the
  same in it as in every `~RX`.
  """
  def ascii_digits(source), do: "(?aD)" <> source

  @doc false
  def fetch(key, source, options) do
    case :persistent_term.get(key, nil) do
      nil ->
        regex = Regex.compile!(source, options)
        :persistent_term.put(key, regex)
        regex

      regex ->
        regex
    end
  end
end
