defmodule BuildCalculatorWeb.InputLimits do
  @moduledoc """
  How much text each input of the web layer may carry, and the ceiling on one
  message from the browser over the LiveView socket (task 4.41).

  Two lines of defence, and this module is where their numbers meet.

    * **First line — the reader.** A pasted text is cut on the server before
      anything reads it (`BuildCalculator.Paste`, the import's
      `Import.Scan.max_bytes/0` and the game log's `GameLog.max_bytes/0`, both
      64 000 bytes), and the reader says so with a note. A search query is cut
      the same way (`query/1`): every candidate name is matched against the
      whole query, so its length is the cost of the search (a 500 000-letter
      query took 17.7 s over the feats of `siala_41`, 120 letters — 5 ms).
    * **Second line — the socket.** One message from the browser may not be
      longer than `BuildCalculatorWeb.Endpoint.max_message_bytes/0`; past it
      the server closes the connection (close code 1009) and the client
      reconnects. The ceiling lives in the config
      (`:websocket_max_message_bytes`) because it is set twice: per frame on
      the socket (`max_frame_size`) and per message of several frames on the
      server (`max_fragmented_message_size` of Bandit). Chrome sends a long
      message as frames of at most 131 000 bytes, so the per-frame ceiling
      alone would never reach it — measured, task 4.41.
    * **The same ceiling on the other transport.** The LongPoll transport of
      the socket takes one request body of at most the same number of bytes
      (`BuildCalculatorWeb.LongPollBodyLimit`, task 4.74); past it the server
      answers 413 and the client reconnects, as it does on the WebSocket.
    * **A ceiling on HTTP bodies** — the forms that still go over plain HTTP
      (log in, change the password, log out) are a few kilobytes at most:
      `request_body/0`, task 4.76.
    * **Strings where the page sends strings** — an address or an event made
      by hand can put a map or a list where a field is read as text:
      `form/3`, `strings/2`, `within?/2`, task 4.76.

  `maxlength` on every text input keeps a legitimate user inside both lines:
  the browser cuts what is typed or pasted, and nothing a person can put into
  the field makes a message the socket refuses.

  ## Numbers

  `maxlength` does nothing on `type=number`, and a button's value is whatever
  a hand-made event puts there, so the server bounds a number itself before
  reading it: `integer/1`. Without the bound `Integer.parse/1` raises
  `SystemLimitError` on about 1.26 million significant digits — a message well
  inside the socket's ceiling — and the LiveView process went down with it.

  ## How long the paste windows are

  `maxlength` counts UTF-16 code units (Chrome 154: an emoji is two, a line
  break one, a pasted CRLF becomes one LF). A form event sends the value
  percent-encoded inside JSON: a letter or a digit costs one byte of the
  message, a Cyrillic letter six, a three-byte character of UTF-8 (CJK,
  U+FFFD, U+200B) nine — the worst; an emoji twelve, six per code unit.

  The windows get one unit more than the reader's ceiling in bytes. A text
  of that many units is always longer than the ceiling (a code unit is at
  least one byte of UTF-8), so a paste the browser had to cut is still cut by
  the reader — and the reader's note about the cut stays on screen. The worst
  legitimate message is then 9 × 64 001 bytes ≈ 0.58 MB; the socket takes up
  to 2 MB.
  """

  alias BuildCalculator.GameLog
  alias BuildCalculatorWeb.Builder.Import.Scan

  # Самое длинное, что ищут глазами, — имя сохранённого билда (120 знаков,
  # `Library.Build`); имена фитов, заклинаний, навыков и оружия короче
  # вдвое и больше. Один предел на все поля поиска и код приглашения.
  @short_text 120

  # Пределы аккаунта — те же числа, что у `Accounts.User` (`validate_length`):
  # длиннее поле ничего законного не несёт. Совпадение стережёт тест.
  @email 160
  @password 72

  # Задача 4.74: самое длинное число, которое сервер разбирает из строки
  # клиента. Поле числа значит самое большее три знака со знаком (граница формы
  # «Вещей» ±255, уровень не выше капа, индекс строки), заголовок
  # `content-length` LongPoll — до 19 цифр; 32 знака оставляют место ведущим
  # нулям и дробной части, набранным руками, а разбор 32 цифр не стоит ничего.
  # Без предела: 1 000 000 цифр — 167 мс, ~1,26 млн значащих — `SystemLimitError`
  # (замер 4.74, OTP 29, `tmp/4.74/intparse.exs`).
  @number_text 32

  # Задача 4.76: потолок тела HTTP-запроса — доводы у `request_body/0`.
  @request_body 16_000

  @doc """
  The ceiling on the body of an HTTP request, in bytes (task 4.76) —
  `Plug.Parsers` in the endpoint answers 413 past it.

  Before it the parsers kept their defaults: 1 MB for a form, 8 MB for JSON
  and multipart — read and parsed (multipart parts written to temporary
  files) on any path, before the router and before the CSRF check refuses
  the request. The application takes JSON and multipart nowhere.

  What legitimately arrives in a body is three small forms: logging in
  (`/users/log-in`: email, password, the remember flag, the CSRF token — or the
  magic-link token instead), changing the password (`/users/update-password`:
  email, password twice) and logging out (`_method` and the token). The
  LiveView socket's LongPoll bodies never reach the parsers — the socket is
  dispatched before them and has its own ceiling
  (`BuildCalculatorWeb.LongPollBodyLimit`). The worst of the three forms — every
  field at its `maxlength`, every unit a three-byte character, nine bytes
  percent-encoded — is under 3 KB (`input_limits_test.exs` computes it); the
  ceiling leaves five times that.
  """
  @spec request_body() :: pos_integer()
  def request_body, do: @request_body

  @doc "`maxlength` of the text import window: one unit over the reader's ceiling."
  @spec import_text() :: pos_integer()
  def import_text, do: Scan.max_bytes() + 1

  @doc "`maxlength` of the game log window: one unit over the reader's ceiling."
  @spec game_log_text() :: pos_integer()
  def game_log_text, do: GameLog.max_bytes() + 1

  @doc "`maxlength` of a search field and of the group invite code."
  @spec short_text() :: pos_integer()
  def short_text, do: @short_text

  @doc "`maxlength` of an email field."
  @spec email() :: pos_integer()
  def email, do: @email

  @doc "`maxlength` of a password field."
  @spec password() :: pos_integer()
  def password, do: @password

  @doc """
  A search query as the server takes it: at most `short_text/0` characters.
  Anything that is not a string — a map or a list a hand-made event can carry —
  is no query at all.
  """
  @spec query(term()) :: String.t()
  def query(text) when is_binary(text), do: String.slice(text, 0, @short_text)
  def query(_text), do: ""

  @doc """
  The text fields of one form as the server takes them (task 4.76): the fields
  named in `fields`, and only those whose value is a string.

  `params` is what arrived — an event's value or a request's params — and
  `name` the form inside it (`"user"` for `user[email]`). A browser sends every
  field of a form as a string, but a hand-made event or address can put a map
  or a list in its place (`?q[a]=1`, `user[email][x]=1`), and the screens read
  these values as text: a map in a field crashed `to_form/2` rendering
  (`Phoenix.HTML.Safe` has no clause for maps), a search with it crashed the
  query (`Library.Query`), a lookup with it crashed the context's guard. A
  value that is not a string is dropped, as if the field had not been sent; a
  field the form does not have is dropped too, so a hand-made event cannot set
  what the form never offers.

  Lengths are not cut here: a changeset says «too long» about its own fields,
  a search cuts its query (`query/1`), a lookup refuses what no stored value
  can be (`within?/2`).
  """
  @spec form(term(), String.t(), [String.t()]) :: %{optional(String.t()) => String.t()}
  def form(%{} = params, name, fields) when is_binary(name),
    do: strings(Map.get(params, name), fields)

  def form(_params, _name, _fields), do: %{}

  @doc """
  The named fields of `params` whose value is a string — `form/3` for fields
  that are not nested in a form (the library's filters, `?q=…&class=…`).
  """
  @spec strings(term(), [String.t()]) :: %{optional(String.t()) => String.t()}
  def strings(%{} = params, fields) when is_list(fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      case Map.get(params, field) do
        value when is_binary(value) -> Map.put(acc, field, value)
        _missing_or_not_a_string -> acc
      end
    end)
  end

  def strings(_params, _fields), do: %{}

  @doc """
  Whether `text` is a string of at most `max` characters — the longest value
  the field it is looked up by can hold (`email/0` for an account's address).
  A longer one cannot be found, so it is not looked up at all; counting stops
  one character past `max`, whatever the length of the string.
  """
  @spec within?(term(), pos_integer()) :: boolean()
  def within?(text, max) when is_binary(text) and is_integer(max) and max > 0,
    do: text |> String.slice(0, max + 1) |> String.length() <= max

  def within?(_text, _max), do: false

  @doc """
  An integer the client sent as a string, read as `Integer.parse/1` reads it —
  but only out of a string of at most #{@number_text} bytes. A longer string, and
  anything that is not a string (a hand-made event can carry a number, a map or
  a list where the page sends text), is `:error`: the value is dropped, the
  caller answers as it does to any other garbage. No field means a number that
  long — the longest it means is three digits and a sign.
  """
  @spec integer(term()) :: {integer(), String.t()} | :error
  def integer(text) when is_binary(text) and byte_size(text) <= @number_text,
    do: Integer.parse(text)

  def integer(_text), do: :error

  @doc "The longest string `integer/1` reads, in bytes."
  @spec number_text() :: pos_integer()
  def number_text, do: @number_text
end
