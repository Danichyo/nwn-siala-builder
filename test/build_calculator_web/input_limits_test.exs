defmodule BuildCalculatorWeb.InputLimitsTest do
  @moduledoc """
  Числа полей ввода и их связь с потолком сообщения сокета — задача 4.41
  (`BuildCalculatorWeb.InputLimits`).

  Два обещания модуля проверяются арифметикой, а не на слово:

    * окно вставки, обрезанное браузером по `maxlength`, всё равно длиннее
      потолка чтения — замечание об обрезке остаётся на экране;
    * худшая законная вставка длиной `maxlength` проходит в одно сообщение
      сокета с запасом.

  Цена символа — замер 4.41 (Chrome 154, `Input.insertText` в окно вставки,
  кадр из `Network.webSocketFrameSent`, `tmp/4.41/exp_charcost.py`): событие
  формы шлёт значение процентной кодировкой внутри JSON — буква 1 байт,
  кириллица 6, трёхбайтный символ UTF-8 (CJK, U+FFFD, U+200B) 9, эмодзи 12 на
  две единицы `maxlength`; обвязка события — 186 байт (окно лога, 159 у окна
  импорта). Живой кадр окна лога на 64 001 знаке «漢» — 576 195 байт.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{GameLog, Paste}
  alias BuildCalculator.Accounts.User
  alias BuildCalculatorWeb.{Endpoint, InputLimits}
  alias BuildCalculatorWeb.Builder.Import.Scan

  @worst_bytes_per_unit 9
  @envelope_bytes 186
  # Запас: худшее законное сообщение помещается в потолок хотя бы трижды —
  # обвязка события растёт с номерами ссылок и полями формы, цена символа
  # меряна в одном браузере.
  @headroom 3

  @windows [
    {"окно импорта текста", &Scan.max_bytes/0, &InputLimits.import_text/0},
    {"окно лога `.билд`", &GameLog.max_bytes/0, &InputLimits.game_log_text/0}
  ]

  describe "окна вставки" do
    for {name, ceiling, maxlength} <- @windows do
      @ceiling ceiling
      @maxlength maxlength

      test "#{name}: текст из одних букв длиной maxlength читатель обрезает с замечанием" do
        max_bytes = @ceiling.()
        maxlength = @maxlength.()

        assert maxlength > max_bytes
        {text, notes} = Paste.take(String.duplicate("a", maxlength), max_bytes)
        assert byte_size(text) == max_bytes
        assert {:text_clipped, max_bytes} in notes

        # и на единицу короче — уже нет: предел не с запасом «на всякий случай»,
        # а ровно там, где обрезка начинается
        assert {_text, []} = Paste.take(String.duplicate("a", maxlength - 1), max_bytes)
      end

      test "#{name}: худшая законная вставка проходит в сообщение сокета с запасом" do
        worst = @worst_bytes_per_unit * @maxlength.() + @envelope_bytes
        assert worst * @headroom <= Endpoint.max_message_bytes()
      end
    end
  end

  describe "query/1 — запрос поиска, как его берёт сервер" do
    test "длинный обрезается до short_text/0 знаков, короткий не меняется" do
      assert InputLimits.query(String.duplicate("ж", 10_000)) ==
               String.duplicate("ж", InputLimits.short_text())

      assert InputLimits.query("pwatk") == "pwatk"
      assert InputLimits.query("") == ""
    end

    test "не строка — пустой запрос" do
      assert InputLimits.query(nil) == ""
      assert InputLimits.query(%{"x" => "y"}) == ""
      assert InputLimits.query(["a"]) == ""
    end
  end

  describe "form/3 и strings/2 — поля формы, как их берёт сервер (задача 4.76)" do
    test "только названные поля и только строки" do
      params = %{
        "user" => %{
          "email" => "a@b.c",
          "password" => %{"x" => "1"},
          "token" => ["t"],
          "role" => "admin"
        }
      }

      assert InputLimits.form(params, "user", ~w(email password token)) == %{"email" => "a@b.c"}
    end

    test "формы нет или она не карта — пустая форма" do
      assert InputLimits.form(%{}, "user", ~w(email)) == %{}
      assert InputLimits.form(%{"user" => "x"}, "user", ~w(email)) == %{}
      assert InputLimits.form(%{"user" => ["x"]}, "user", ~w(email)) == %{}
      # нагрузка события-хука бывает любым JSON
      assert InputLimits.form("x", "user", ~w(email)) == %{}
      assert InputLimits.form(nil, "user", ~w(email)) == %{}
    end

    test "длина не режется — её говорит changeset или поиск" do
      long = String.duplicate("x", 10_000)
      assert InputLimits.strings(%{"q" => long, "a" => 1}, ~w(q a)) == %{"q" => long}
      assert InputLimits.strings("q", ~w(q)) == %{}
    end
  end

  describe "within?/2 — можно ли такое искать (задача 4.76)" do
    test "по знакам, а не по байтам" do
      assert InputLimits.within?(String.duplicate("ж", 160), 160)
      refute InputLimits.within?(String.duplicate("ж", 161), 160)
      assert InputLimits.within?("", 160)
    end

    test "длинная строка — нет, и считать до конца не нужно" do
      refute InputLimits.within?(String.duplicate("x", 2_000_000), InputLimits.email())
    end

    test "не строка — нет" do
      refute InputLimits.within?(nil, 160)
      refute InputLimits.within?(%{"a" => "b"}, 160)
      refute InputLimits.within?(["a"], 160)
    end
  end

  describe "request_body/0 — тело HTTP-запроса (задача 4.76)" do
    # Худшие законные тела трёх форм, что ходят по HTTP: каждое поле
    # на своём `maxlength`, каждая единица — трёхбайтный символ (9 байт
    # процентной кодировкой, худшее по замеру 4.41), токен CSRF настоящий.
    defp worst_bodies do
      csrf = Plug.CSRFProtection.get_csrf_token()
      wide = fn units -> String.duplicate("漢", units) end
      email = wide.(InputLimits.email())
      password = wide.(InputLimits.password())

      [
        log_in: %{
          "_csrf_token" => csrf,
          "user" => %{"email" => email, "password" => password, "remember_me" => "true"}
        },
        magic_link: %{
          "_csrf_token" => csrf,
          "_action" => "confirmed",
          "user" => %{"token" => String.duplicate("A", 43), "remember_me" => "true"}
        },
        update_password: %{
          "_csrf_token" => csrf,
          "user" => %{
            "email" => email,
            "password" => password,
            "password_confirmation" => password
          }
        },
        log_out: %{"_csrf_token" => csrf, "_method" => "delete"}
      ]
      |> Enum.map(fn {form, params} -> {form, byte_size(Plug.Conn.Query.encode(params))} end)
    end

    test "худшее законное тело меньше потолка впятеро" do
      bodies = worst_bodies()
      {worst_form, worst} = Enum.max_by(bodies, &elem(&1, 1))

      # Положительный контроль: тела посчитаны, а не нули, и худшее — смена
      # пароля (почта и пароль дважды).
      assert worst_form == :update_password
      assert worst > 2_500

      assert worst * 5 <= InputLimits.request_body()
    end

    test "потолок на порядки ниже прежних умолчаний парсеров (1 МБ формы, 8 МБ JSON)" do
      assert InputLimits.request_body() * 50 < 1_000_000
    end
  end

  describe "integer/1 — число из строки клиента (задача 4.74)" do
    # Положительный контроль: без предела такое число роняет разбор — на нём
    # и падал процесс экрана (`gear_number/1`, 4.41: ~1,26 млн значащих цифр).
    test "число в 2 млн цифр ломает голый Integer.parse/1, а integer/1 отвечает :error" do
      huge = String.duplicate("7", 2_000_000)

      assert_raise SystemLimitError, fn -> Integer.parse(huge) end
      assert InputLimits.integer(huge) == :error
    end

    test "в пределах — ровно как Integer.parse/1" do
      for text <- ["12", "-3", "0", "+5", "5abc", "", "x", "1.5", "007"] do
        assert InputLimits.integer(text) == Integer.parse(text), inspect(text)
      end

      at_limit = String.duplicate("9", InputLimits.number_text())
      assert {_n, ""} = InputLimits.integer(at_limit)
      assert InputLimits.integer(at_limit <> "9") == :error
      # ведущие нули тоже длина: строка, а не значение
      assert InputLimits.integer(String.duplicate("0", InputLimits.number_text()) <> "7") ==
               :error
    end

    test "не строка — :error, а не FunctionClauseError" do
      for value <- [nil, 5, 1.5, %{"a" => "1"}, ["1"], true] do
        assert InputLimits.integer(value) == :error, inspect(value)
      end
    end

    test "предел длиннее любого числа, которое поле значит, и длины content-length" do
      # граница формы «Вещей» ±255, уровень — две цифры, `content-length` до 2^64
      assert InputLimits.number_text() >= byte_size("-255")
      assert InputLimits.number_text() >= byte_size(Integer.to_string(2 ** 64))
    end
  end

  describe "поля аккаунта — пределы схемы `User`" do
    test "почта" do
      %Ecto.Changeset{validations: validations} =
        User.email_changeset(%User{}, %{email: "a@b.c"}, validate_unique: false)

      assert Keyword.get(Keyword.get_values(validations, :email) |> lengths(), :max) ==
               InputLimits.email()
    end

    test "пароль" do
      %Ecto.Changeset{validations: validations} =
        User.password_changeset(%User{}, %{password: "long enough password"},
          hash_password: false
        )

      assert Keyword.get(Keyword.get_values(validations, :password) |> lengths(), :max) ==
               InputLimits.password()
    end
  end

  defp lengths(rules),
    do:
      Enum.find_value(rules, fn
        {:length, opts} -> opts
        _ -> nil
      end)
end
