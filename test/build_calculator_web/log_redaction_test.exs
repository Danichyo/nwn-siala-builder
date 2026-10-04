defmodule BuildCalculatorWeb.LogRedactionTest do
  @moduledoc """
  Фильтр лога `BuildCalculatorWeb.LogRedaction` (задача 4.75) — по формам
  событий, на синтетике: настоящие пути до него проходит сторож
  `log_leak_test.exs`, а здесь — то, чего сторож своими сценариями
  не достаёт (падение при входе, `KeyError` по ассайнам, задача, чужая строка
  с кодом), и то, что фильтр обязан НЕ трогать.

  Фильтр зовётся как функция (`redact/1`, `filter/2`), а текст события
  собирает переводчик отчётов Elixir (`Logger.Translator`) — тем же путём,
  что в проде. Общих настроек тест не трогает — `async: true`.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.{Data, Encoding}
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.LogRedaction
  alias BuildCalculatorWeb.LogRedaction.Withheld

  @dan_code "../fixtures/dan_build_2026-09-13.code"
            |> Path.expand(__DIR__)
            |> File.read!()
            |> String.trim()

  @uuid "98536704-499d-40cd-a2c9-c7cc4a659ca4"

  defp string_event(text, meta \\ %{}),
    do: %{level: :info, msg: {:string, text}, meta: Map.merge(%{time: 1, pid: self()}, meta)}

  defp text_of(%{msg: {:string, text}}), do: IO.chardata_to_string(text)

  # Текст отчёта — так, как его напечатает переводчик Elixir на уровне `:info`.
  defp translated(%{msg: {:report, report}}) do
    {:ok, chardata, _meta} =
      Logger.Translator.translate(:info, :error, :report, {:logger, report})

    IO.chardata_to_string(chardata)
  end

  defp windows(text), do: for(at <- 0..(byte_size(text) - 8), do: binary_part(text, at, 8))

  defp leaks?(text, secret), do: Enum.any?(windows(secret), &String.contains?(text, &1))

  describe "код билда по форме" do
    test "любой код, который выдаёт Encoding, сводится к пометке целиком" do
      ruleset = Data.ruleset!("siala_41")
      empty = Encoding.encode(Build.new(ruleset_version: ruleset.version))
      {:ok, %{build: build}} = Encoding.decode(@dan_code)

      codes = [empty, @dan_code, Encoding.encode(Build.truncate(build, 1))]

      for code <- codes do
        assert LogRedaction.text("x #{code} y") == "x [build code] y"
        assert LogRedaction.text("/b/#{code}") == "/b/[build code]"
        assert LogRedaction.text("b%3D#{code}&") == "b%3D[build code]&"
        assert LogRedaction.text("to=%2Fb%2F#{code}") == "to=%2Fb%2F[build code]"
        assert LogRedaction.text(~s(%{"b" => "#{code}"})) == ~s(%{"b" => "[build code]"})
      end

      # Восемь знаков после точки — меньше самого короткого кода (пустой билд).
      assert byte_size(empty) - 2 > 8
    end

    test "код в charlist и внутри терма" do
      event = %{
        level: :error,
        msg: {~c"~p", [%{"b" => @dan_code, cl: String.to_charlist(@dan_code)}]},
        meta: %{}
      }

      %{msg: {_format, [args]}} = LogRedaction.redact(event)

      refute leaks?(inspect(args), @dan_code)
      assert args["b"] == "[build code]"
    end

    test "обычный текст лога не трогается" do
      for text <- [
            "GET /b/:code",
            "Sent 200 in 12ms",
            "Elixir 1.20.2, OTP 29, 203.0.113.7, 21:54:23.311",
            "(build_calculator 0.1.0) lib/build_calculator_web/live/builder_live.ex:615",
            "BuildCalculatorWeb.BuilderLive.handle_event/3",
            "request_id=GNtoZdCk8nG9MFUAAAAB",
            "Serializer: Phoenix.Socket.V2.JSONSerializer",
            "↳ :elixir_compiler_1.__FILE__/1, at: tmp/x.exs:13",
            "Origin of the request: https://evil.example.com"
          ] do
        assert LogRedaction.text(text) == text
      end
    end
  end

  describe "адрес в тексте — хост и шаблон маршрута" do
    test "предупреждение LiveView о переходе между live_session" do
      for {url, expected} <- [
            {"http://localhost:4000/?b=#{@dan_code}", "http://localhost:4000/?…"},
            {"https://builder.dondryanich.ru/b/#{@dan_code}",
             "https://builder.dondryanich.ru/b/:code"},
            {"http://www.example.com/builds/#{@uuid}/edit",
             "http://www.example.com/builds/:id/edit"},
            {"http://x.test/no/such/#{@uuid}", "http://x.test/(unmatched path)"}
          ] do
        warning =
          "navigate event to #{inspect(url)} failed because you are redirecting across " <>
            "live_sessions. A full page reload will be performed instead"

        text = warning |> string_event() |> LogRedaction.redact() |> text_of()
        assert text =~ inspect(expected)
        refute leaks?(text, @dan_code)
        refute text =~ @uuid
      end
    end
  end

  describe "отчёт о падении процесса" do
    defp terminate_report(last_message, stack_args) do
      socket_like = %{assigns: %{code: @dan_code, build_id: @uuid}}

      %{
        level: :error,
        msg:
          {:report,
           %{
             label: {:gen_server, :terminate},
             name: self(),
             last_message: last_message,
             state: %{socket: socket_like},
             reason:
               {%FunctionClauseError{module: M, function: :f, arity: length(stack_args)},
                [{M, :f, stack_args, [file: ~c"lib/m.ex", line: 1]}]},
             client_info: nil,
             log: [],
             process_label: {Phoenix.LiveView, M, "lv:phx-x"}
           }},
        meta: %{error_logger: %{tag: :error}, domain: [:otp]}
      }
    end

    test "вход в LiveView: адрес с кодом в последнем сообщении, сокет в аргументах" do
      join =
        {Phoenix.Channel, %{"url" => "http://h/b/#{@dan_code}", "session" => "SFMy"}, self(),
         :socket}

      event = terminate_report(join, [%{"code" => @dan_code}, %{id: @uuid}])

      control = translated(event)
      assert leaks?(control, @dan_code), "контроль: без фильтра отчёт несёт код"

      text = event |> LogRedaction.redact() |> translated()
      refute leaks?(text, @dan_code)
      refute text =~ @uuid
      assert text =~ "M.f/2"
      assert text =~ "#Withheld<{Phoenix.Channel, …} of 4>"
    end

    test "кто звал упавший процесс — остаётся, стек вызывающего — с арностью" do
      event = terminate_report(:boom, [:a])
      {:report, report} = event.msg
      client = {self(), {:caller, [{M, :g, [@uuid], [file: ~c"lib/g.ex", line: 2]}]}}
      event = %{event | msg: {:report, %{report | client_info: client}}}

      %{msg: {:report, clean}} = LogRedaction.redact(event)

      assert {pid, {:caller, [{M, :g, 1, _}]}} = clean.client_info
      assert pid == self()
      assert clean.last_message == :boom
    end

    test "событие LiveView: имя события остаётся, полезная нагрузка — нет" do
      message = %Phoenix.Socket.Message{
        topic: "lv:phx-x",
        event: "event",
        payload: %{"event" => "pick_feat", "value" => %{"feat" => "weapon_focus", "q" => @uuid}}
      }

      text = message |> terminate_report([:a]) |> LogRedaction.redact() |> translated()

      assert text =~ ~s(payload.event: "pick_feat")
      refute text =~ "weapon_focus"
      refute text =~ @uuid
    end

    test "KeyError по ассайнам: карта не печатается, ключ — да" do
      error = %KeyError{key: :missing, term: %{code: @dan_code, id: @uuid}}
      clean = LogRedaction.exception(error)

      assert Exception.message(clean) =~ "key :missing not found in: #Withheld<map, 2 keys>"
      refute Exception.message(clean) =~ @uuid
      assert Exception.message(error) =~ @uuid, "контроль: без фильтра карта печатается"
    end

    test "исключения со значением: MatchError, CaseClauseError, Protocol.UndefinedError" do
      for error <- [
            %MatchError{term: {:ok, @uuid}},
            %CaseClauseError{term: [@uuid]},
            %Protocol.UndefinedError{protocol: Enumerable, value: %{id: @uuid}}
          ] do
        assert Exception.message(error) =~ @uuid
        refute Exception.message(LogRedaction.exception(error)) =~ @uuid
      end
    end

    test "текст исключения проходит сеть" do
      clean = LogRedaction.exception(%RuntimeError{message: "bad code #{@dan_code}"})
      assert clean.message == "bad code [build code]"
    end

    test "задача Task.Supervisor: аргументы не печатаются" do
      event = %{
        level: :error,
        msg:
          {:report,
           %{
             label: {Task.Supervisor, :terminating},
             report: %{
               name: self(),
               starter: self(),
               function: &String.length/1,
               args: [@uuid],
               reason: {%RuntimeError{message: "x"}, [{M, :f, [@uuid], []}]},
               process_label: :undefined
             }
           }},
        meta: %{}
      }

      %{msg: {:report, report}} = LogRedaction.redact(event)

      {:ok, text, _meta} =
        Logger.Translator.translate(:info, :error, :report, {report.label, report.report})

      refute IO.chardata_to_string(text) =~ @uuid
      assert IO.chardata_to_string(text) =~ "#Withheld<list, 1 items>"
    end
  end

  describe "строка ошибки Bandit" do
    defp bandit_event(text, crash_reason) do
      string_event(text, %{
        crash_reason: crash_reason,
        domain: [:bandit],
        conn: %Plug.Conn{request_path: "/builds/#{@uuid}"}
      })
    end

    test "Exception.format/3 собирается заново — без аргументов кадров" do
      error = %FunctionClauseError{module: M, function: :crash, arity: 2}

      stack = [
        {M, :crash, [@dan_code, %{path: "/builds/#{@uuid}"}], [file: ~c"lib/m.ex", line: 3]}
      ]

      original = Exception.format(:error, error, stack)
      assert original =~ @uuid, "контроль: Bandit печатает аргументы"

      clean = LogRedaction.redact(bandit_event(original, {error, stack}))

      assert text_of(clean) =~ "M.crash/2"
      refute text_of(clean) =~ @uuid
      refute leaks?(text_of(clean), @dan_code)
      refute Map.has_key?(clean.meta, :conn)
      assert {%FunctionClauseError{}, [{M, :crash, 2, _}]} = clean.meta.crash_reason
    end

    test "текст другой формы — только сеть" do
      error = %RuntimeError{message: "x"}
      clean = LogRedaction.redact(bandit_event("not the format #{@dan_code}", {error, []}))
      assert text_of(clean) == "not the format [build code]"
    end
  end

  describe "фильтр не роняет лог" do
    test "событие странной формы — без содержимого или :stop, но не исключение" do
      assert :stop = LogRedaction.filter(%{level: :info, msg: {:string, [:x]}, meta: :none}, [])

      broken = %{level: :info, msg: {:string, [:not_chardata]}, meta: %{time: 1, secret: @uuid}}
      assert %{msg: {:string, text}, meta: meta} = LogRedaction.filter(broken, [])
      assert text =~ "log event withheld"
      refute Map.has_key?(meta, :secret)
    end

    test "пометка печатается видом и размером" do
      assert inspect(LogRedaction.withhold(%{a: 1, b: 2})) == "#Withheld<map, 2 keys>"
      assert inspect(LogRedaction.withhold("abc")) == "#Withheld<binary, 3 bytes>"
      assert inspect(LogRedaction.withhold(%URI{})) == "#Withheld<%URI{}>"
      assert LogRedaction.withhold(:boom) == :boom
      assert %Withheld{} = LogRedaction.withhold([1])
    end
  end
end
