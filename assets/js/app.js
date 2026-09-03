// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/build_calculator"
import topbar from "../vendor/topbar"

// ───────────────────────────────────────────────────────────────────────────
// ЖИВУЧЕСТЬ СОЕДИНЕНИЯ НА МОБИЛЬНОМ (AGENT_QUEUE §3.32, жалоба Dan 15.08.2026:
// «сворачиваю Chrome на Андроиде — соединение пропадает до обновления страницы»)
//
// Три отдельных дефекта складывались в один симптом. Все три ЧИТАЮТСЯ
// в исходниках `deps/phoenix/assets/js/phoenix/socket.js` и
// `deps/phoenix_live_view/.../live_socket.ts` — это не догадки:
//
//  1. Порог фолбэка `longPollFallbackMs: 2500` (значение из генератора Phoenix,
//     его никто не выбирал под мобильную сеть) срабатывает ложно. Причём
//     порог применяется ДВАЖДЫ: сначала на открытие вебсокета, а потом ещё
//     раз — на ответ `ping` уже ПОСЛЕ открытия (`connectWithFallback`,
//     «give the fallback a new period to attempt ping»). То есть даже мгновенно
//     открывшийся вебсокет теряется, если round-trip не уложился в порог.
//     Замер прода 15.08.2026: два подключения из семи ушли в лонгполл, при том
//     что рукопожатие вебсокета отвечает 101 Switching Protocols.
//
//  2. 🔴 Деградация НЕОБРАТИМА, и это главная находка. Уйдя в лонгполл,
//     phoenix.js пишет `phx:fallback:LongPoll` в sessionStorage (условие —
//     вебсокет ни разу не прошёл health check), а `connect()` пробует вебсокет
//     только при `transport !== LongPoll`. sessionStorage переживает
//     перезагрузку страницы — значит вкладка приколочена к лонгполлу
//     до её ЗАКРЫТИЯ. Достаточно один раз не повезти с сетью. Отсюда и «каждый
//     раз воспроизводится», и лонгполл при обычной загрузке страницы в логах.
//
//  3. У лонгполла НЕТ детектора живости: `LongPoll.skipHeartbeat = true`,
//     и `resetHeartbeat()` для него не делает ничего. Мёртвое соединение
//     обнаруживается только завершением висящего XHR, а библиотечный
//     обработчик `visibilitychange` переподключается лишь при `!isConnected()`.
//     Полуоткрытый лонгполл (вкладку заморозили, XHR повис) он не видит вовсе.
//     У вебсокета таких детекторов два: событие close от браузера и heartbeat
//     каждые 30 с — поэтому он и переживает сворачивание, а лонгполл нет.
//
//  4. Есть и путь залипания, НЕ зависящий от транспорта. По `pagehide`
//     phoenix.js зовёт `disconnect()`, а тот ставит `closeWasClean = true`
//     и сбрасывает `reconnectTimer`. После этого встать может только
//     обработчик `pageshow` — и только если `connectClock` за это время
//     не изменился. Не пришёл `pageshow` (или кто-то тронул сокет) — сессия
//     мертва до перезагрузки страницы, хотя «отключились» мы штатно.
//     Поэтому сторож ниже смотрит на ФАКТИЧЕСКОЕ состояние соединения,
//     а не на флаги библиотеки: `closeWasClean` тут врёт по построению.
//
//  5. 🔴 И ПЯТЫЙ, найденный только замером (3.67, Dan 28.08.2026): на Android
//     возврат к ЗАМОРОЖЕННОЙ вкладке даёт `resume` и НЕ даёт `visibilitychange`.
//     Четыре дефекта выше — про то, что механизм ошибается; этот про то, что он
//     не запускается вовсе. Оба обработчика (наш и апстримовский) подписаны
//     на `visibilitychange`, третий путь апстрима — на `pageshow`, а `pagehide`
//     в этом сценарии не приходит ни разу, значит и `pageshow` быть не может.
//     Не наступает НИ ОДНО из трёх — и мёртвый сокет остаётся мёртвым, хотя
//     условие апстрима (`!isConnected() && !closeWasClean`) выполнено.
//     Лечится подпиской на `resume` в конце файла.
// ───────────────────────────────────────────────────────────────────────────

// ⚠️ ФОЛБЭК В ЛОНГПОЛЛИНГ ВЫКЛЮЧЕН — решение Dan 15.08.2026, и оно опирается
// на замер, а не на предпочтение. Отсутствие `longPollFallbackMs` в опциях
// ниже и есть выключение: в phoenix.js фолбэк включается только этой опцией.
//
// Здесь стоял порог 8000 (подняли с генераторных 2500). Порог не помог, и вот
// почему — лог прода 15.08.2026:
//
//     15:17:56  CONNECTED ... Transport: :websocket
//     15:17:58  CONNECTED ... Transport: :longpoll     ← через 1.9 с
//
// Полторы секунды — это МЕНЬШЕ порога, то есть фолбэк сработал не по таймауту,
// а по ошибке: вебсокет успел открыться и почти сразу умер (пользователь свернул
// браузер), а `connectWithFallback` трактует ошибку до первого удачного ping как
// «вебсокет тут не работает» и уходит в лонгполл. **Порог такое не ловит по
// построению** — про это прямо сказано в комментарии, который тут стоял, но
// вывод из него сделан не был.
//
// Дальше цепочка добивает: лонгполл не переживает заморозки вкладки
// (детектора живости у него нет вовсе, `skipHeartbeat = true`), и сессия висит
// мёртвой до перезагрузки страницы. Ровно жалоба Dan.
//
// Что мы этим теряем: у кого вебсокет режет прокси или антивирус, приложение
// перестанет работать вовсе, а не переползёт на запасной транспорт. Осознанно:
// вебсокет на этом сервере доказанно работает (рукопожатие отвечает 101),
// аудитория — полсотни игроков одного шарда, и цена ошибки несимметрична —
// мёртвая вкладка у всех мобильных против недоступности у редких.
//
// ⚠️ Транспорт на СЕРВЕРЕ (`endpoint.ex`) специально оставлен включённым:
// вернуть фолбэк — одна строка `longPollFallbackMs: 8000` в опциях ниже,
// правки сервера и передеплоя схемы для этого не нужно.

// Сколько ждать ответа на ping, прежде чем счесть открытое соединение мёртвым.
// Пинг идёт по УЖЕ установленному соединению, то есть это чистый round-trip:
// на мобильной сети после пробуждения радио он бывает секундным, но не
// пятисекундным. Половина библиотечного push timeout (10 000 мс) — мы
// шевелимся раньше, чем LiveView начнёт сыпать таймаутами пушей.
const PING_DEADLINE_MS = 5000

// Фора библиотеке. Её собственный `visibilitychange` в phoenix.js уже пытается
// встать сам, и перебивать идущую попытку значит удлинять простой. Вмешиваемся
// только через это время и только если попытки не видно вовсе.
const GRACE_MS = 3000

// Форсировать переподключение не чаще, чем раз в этот срок. Это защита от
// самораскрутки: у кого вебсокет не работает в принципе, наш возврат к нему
// закончится мгновенным фолбэком обратно, и без этого замка события `online`
// на мигающей сети крутили бы цикл. Заведомо больше одного полного цикла
// проверки (GRACE + PING_DEADLINE = 8 с).
const MIN_FORCE_INTERVAL_MS = 15000

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

const socket = liveSocket.getSocket()

// Ключ памяти о фолбэке. Имя транспорта берём у самого сокета: phoenix.js
// специально возвращает его строкой «LongPoll», устойчивой к минификации
// (`transportName`). Константа рядом — на случай, если метод однажды исчезнет:
// тогда `removeItem` станет холостым, и мы вернёмся к сегодняшнему поведению,
// а не сломаемся.
const longPollFallbackKey = (() => {
  const longPoll = socket.getLongPollTransport && socket.getLongPollTransport()
  const name = (longPoll && socket.transportName && socket.transportName(longPoll)) || "LongPoll"
  return `phx:fallback:${name}`
})()

// ⚠️ Снятие метки фактически отключает мемоизацию фолбэка, и это сознательно.
// Она экономит время только тому, у кого вебсокет «принимает и молчит» (все
// остальные получают ошибку и мгновенный фолбэк), и платит за эту экономию
// пожизненной деградацией вкладки. У нас цена ошибки несимметрична: лишние
// секунды ожидания раз в полную загрузку страницы против сессии, которая
// не переживает сворачивания браузера.
const forgetLongPollFallback = () => {
  try {
    window.sessionStorage.removeItem(longPollFallbackKey)
  } catch (_e) {
    // приватный режим или заблокированное хранилище — не наша беда
  }
}

const onLongPoll = () =>
  !!socket.getLongPollTransport && socket.transport === socket.getLongPollTransport()

let lastForceAt = 0
let pingPending = false

const forceReconnect = (reason) => {
  const now = Date.now()
  if(now - lastForceAt < MIN_FORCE_INTERVAL_MS){ return }
  lastForceAt = now
  console.info(`[liveSocket] принудительное переподключение: ${reason}`)

  if(onLongPoll() && window.WebSocket){
    // Возврат на вебсокет. Без снятия метки `connect()` первой же строкой
    // `connectWithFallback` уходит обратно в лонгполл с причиной «memorized».
    forgetLongPollFallback()
    // ⚠️ Сначала disconnect, и только потом замена транспорта — порядок
    // ЗАМЕРЕН, а не выбран по вкусу. `replaceTransport` на ещё живом
    // соединении отменяет свежий GET лонгполла (`net::ERR_ABORTED`,
    // проверено через CDP 15.08.2026): библиотека закрывает старый conn
    // асинхронно и успевает задеть новый. После disconnect соединения нет,
    // задевать нечего. `replaceTransport` сам зовёт `connect()`.
    liveSocket.disconnect(() => liveSocket.replaceTransport(window.WebSocket))
  } else {
    liveSocket.disconnect(() => liveSocket.connect())
  }
}

// Проверка живости. Вопрос задаётся СЕРВЕРУ, а не клиенту: на лонгполле
// `isConnected()` остаётся true и у мёртвого соединения (дефект 3 выше).
const checkConnection = (retriesLeft) => {
  if(document.visibilityState !== "visible"){ return }

  const state = socket.connectionState()
  if(state === "connecting" || state === "closing"){
    // Попытка уже идёт — не мешаем, но и не забываем про неё.
    if(retriesLeft > 0){ window.setTimeout(() => checkConnection(retriesLeft - 1), GRACE_MS) }
    return
  }
  if(state !== "open"){ return forceReconnect(`состояние сокета «${state}»`) }

  if(pingPending){ return }
  pingPending = true
  let answered = false
  // ⚠️ Колбэк неотвеченного `ping` остаётся висеть в списке подписчиков
  // сообщений: снять его снаружи нечем, `ping` не отдаёт ref. Пингов единицы
  // (только по событию и не чаще раза в MIN_FORCE_INTERVAL_MS), так что цена —
  // несколько замыканий на вкладку, и она меньше своей реализации heartbeat.
  const sent = socket.ping(() => {
    answered = true
    pingPending = false
  })
  if(!sent){
    pingPending = false
    return forceReconnect("сокет не принял ping")
  }
  window.setTimeout(() => {
    if(answered){ return }
    pingPending = false
    forceReconnect("ping без ответа")
  }, PING_DEADLINE_MS)
}

// Два повтора по GRACE_MS хватает, чтобы переждать чужую попытку соединения
// и не зациклиться: 3 проверки за 9 секунд, дальше ждём следующего события.
// Таймер один на всех: `online` на мигающей сети приходит пачкой, и десять
// отложенных проверок вместо одной ничего не добавляют.
let checkTimer = null
const checkConnectionSoon = () => {
  window.clearTimeout(checkTimer)
  checkTimer = window.setTimeout(() => checkConnection(2), GRACE_MS)
}

window.addEventListener("visibilitychange", () => {
  if(document.visibilityState === "visible"){ checkConnectionSoon() }
})
window.addEventListener("online", checkConnectionSoon)

// 🔴 ПОЧИНКА 3.67, и она стоит на замере, а не на чтении спецификации.
// Лента с телефона Dan 28.08.2026 (Android 10, Chrome 151) показала ровно это:
//
//     visibilitychange → hidden   вкладка ушла в фон, сокет ещё open
//     freeze                      сокет уже closed, clean=false
//     resume            → visible ВЕРНУЛИСЬ
//     ...и всё. `visibilitychange` на возврате не приходит вовсе.
//
// Подтверждено вторым прогоном: после подписки в трейле появились `check`
// (ровно через GRACE_MS) и `force`, а сервер независимо показал CONNECTED
// вебсокетом. Возврат во вкладку → рабочее соединение за 6.0 с.
//
// ⚠️ Это НЕ третий обработчик переподключения, которых план 3.67 запрещал
// плодить. Воронка та же самая — `checkConnectionSoon()`, — значит фора
// библиотеке, дедлайн `ping` и троттлинг работают как работали, и драться
// двум путям не за что: кто пришёл первым, тот и переподключил.
//
// ⚠️ `visibilitychange` не заменён, а ДОПОЛНЕН: на десктопе заморозки нет
// вовсе, `resume` не приходит никогда, и тамошний путь работает — это тоже
// замер Dan («на ПК/маке данной проблемы не существует»).
//
// ⚠️ Событие приходит на `document`, а не на `window` (Page Lifecycle API).
// На `window` подписка молча не сработает — ошибки при этом не будет никакой.
document.addEventListener("resume", checkConnectionSoon)

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Свежая загрузка страницы — свежая попытка вебсокета. Без этого вкладка,
// однажды деградировавшая, стартует в лонгполле до самого своего закрытия
// (дефект 2 выше), и перезагрузка страницы её не лечит.
forgetLongPollFallback()

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

