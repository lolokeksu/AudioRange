import { exec as bridgeExec, hasBridge } from "./ksu-bridge.js";

const CTL = "/data/adb/modules/audiorange/bin/audiorangectl";
const $ = (id) => document.getElementById(id);

let selectedProfile = "stock";
let currentProfile = "stock";
let currentCustom = 60;
let testActive = false;
let countdownTimer = null;
let operationInProgress = false;
let statusLoaded = false;
let compatibility = { knownMax: null, confirmed: new Set(), rejected: new Set(), states: { 30: "untested", 50: "untested", 75: "untested", 100: "untested" } };

function activateView(name, { remember = true } = {}) {
  const available = new Set(["control", "diagnostics", "test"]);
  const target = available.has(name) ? name : "control";
  document.querySelectorAll("[data-view]").forEach((view) => {
    const active = view.dataset.view === target;
    view.hidden = !active;
    view.classList.toggle("active", active);
  });
  document.querySelectorAll("[data-view-target]").forEach((button) => {
    const active = button.dataset.viewTarget === target;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", String(active));
    button.tabIndex = active ? 0 : -1;
  });
  if (remember) {
    try { sessionStorage.setItem("vss-active-view", target); } catch (_) { /* optional */ }
  }
  window.scrollTo({ top: 0, behavior: "smooth" });
}

const profileDescriptions = {
  stock: "Штатный профиль не задаёт собственное значение и сохраняет шкалу текущей прошивки.",
  30: "30 шагов: фиксированный логический максимум. Работа подтверждается только после перезагрузки через AudioService.",
  50: "50 шагов: фиксированный логический максимум. На неизвестной прошивке считается непроверенным.",
  75: "75 шагов: фиксированный логический максимум. Прошивка может принять, ограничить или отклонить значение.",
  100: "100 шагов: фиксированный логический максимум. Даже при подтверждении AudioService соседние уровни могут звучать одинаково из-за OEM-аудиостека или Bluetooth.",
  custom: "Пользовательский профиль: целое значение от 15 до 100. Оно меняет логический диапазон Android, а не усиление."
};

function log(message, replace = false) {
  const node = $("console");
  node.textContent = replace ? message : `${node.textContent}\n${message}`;
  node.scrollTop = node.scrollHeight;
}

async function shell(command) {
  const { errno, stdout, stderr } = await bridgeExec(command);
  if (errno !== 0) throw new Error(stderr || stdout || `Команда завершилась с кодом ${errno}.`);
  return { stdout, stderr };
}

function profileLabel(profile, custom = currentCustom) {
  if (profile === "stock") return "Штатный";
  if (profile === "custom") {
    const numeric = Number(custom);
    return custom !== null && String(custom).trim() !== "" && Number.isInteger(numeric) ? `Свой: ${numeric}` : "Свой: —";
  }
  return `${profile} шагов`;
}

function statusClass(code) {
  if (["CONFIRMED", "STOCK_ACTIVE"].includes(code)) return "good";
  if (["REBOOT_REQUIRED", "PROPERTY_ONLY", "STOCK_UNVERIFIED"].includes(code)) return "warn";
  return "bad";
}

function statusTitle(code) {
  const labels = {
    CONFIRMED: "Подтверждено",
    STOCK_ACTIVE: "Штатный профиль активен",
    REBOOT_REQUIRED: "Нужна перезагрузка",
    PROPERTY_ONLY: "Частично подтверждено",
    STOCK_UNVERIFIED: "Диапазон не прочитан",
    AUDIOSERVICE_MISMATCH: "Диапазон не совпадает",
    PROPERTY_MISMATCH: "Свойство не совпадает"
  };
  return labels[code] || code;
}

function verificationText(code, data) {
  const labels = {
    CONFIRMED: `Системный аудиосервис подтвердил диапазон 0–${data.audioMax}.`,
    STOCK_ACTIVE: `Android использует штатный диапазон ${data.audioMin}–${data.audioMax}.`,
    REBOOT_REQUIRED: "Профиль сохранён, но Android ещё использует предыдущую шкалу.",
    PROPERTY_ONLY: "Свойство Android совпадает, но фактический диапазон системного аудиосервиса прочитать не удалось.",
    STOCK_UNVERIFIED: "Переопределение отключено, но штатный диапазон системного аудиосервиса прочитать не удалось.",
    AUDIOSERVICE_MISMATCH: data.earlyResult === "applied" && data.earlyCurrentBoot ? `Значение ${data.configured} применено до запуска Android-сервисов, но AudioService сохранил максимум ${data.audioMax}. Прошивка игнорирует или переопределяет стандартный параметр.` : `Выбрано ${data.configured}, но системный аудиосервис сообщает максимум ${data.audioMax}.`,
    PROPERTY_MISMATCH: `Свойство Android равно ${data.property}, а выбранный профиль требует ${data.configured}.`
  };
  return labels[code] || `Технический статус: ${code}.`;
}

function verificationAction(code) {
  const actions = {
    CONFIRMED: "Действий не требуется.",
    STOCK_ACTIVE: "Действий не требуется.",
    REBOOT_REQUIRED: "Перезагрузите Android для применения.",
    PROPERTY_ONLY: "После полной загрузки Android повторите диагностику.",
    STOCK_UNVERIFIED: "После полной загрузки Android обновите состояние.",
    AUDIOSERVICE_MISMATCH: "Если раннее применение подтверждено, верните штатный профиль: текущая прошивка не принимает выбранный диапазон.",
    PROPERTY_MISMATCH: "Проверьте источники конфликтов, затем исправьте конфигурацию модуля."
  };
  return actions[code] || "Запустите диагностику.";
}

function propertyLabel(value) {
  return value === "unset" ? "Не переопределено" : value;
}

function rangeLabel(minimum, maximum) {
  return /^\d+$/.test(String(minimum)) && /^\d+$/.test(String(maximum)) ? `${minimum}–${maximum}` : "Не удалось прочитать";
}

function baselineLabel(state, maximum) {
  if (state === "valid") return `0–${maximum}`;
  if (state === "stale") return "Устарел";
  return "Не сохранён";
}

function backendLabel(backend, confidence) {
  const source = backend === "cmd_media_session" ? "cmd media_session" : backend === "unavailable" ? "Недоступен" : backend;
  const precision = confidence === "high" ? "высокая достоверность" : confidence === "medium" ? "средняя достоверность" : "без подтверждения";
  return `${source} · ${precision}`;
}


function romConfidenceLabel(value) {
  if (value === "high") return "Высокая точность определения";
  if (value === "medium") return "Средняя точность определения";
  return "Ориентировочное определение";
}

function integrityLabel(value) {
  if (value === "VERIFIED") return "Подтверждена";
  if (value === "MODIFIED") return "Есть изменённые или повреждённые файлы";
  return "Ещё не проверялась";
}

function conflictLabel(data) {
  const high = Number(data.conflictHigh || 0);
  const medium = Number(data.conflictMedium || 0);
  const low = Number(data.conflictLow || 0);
  if (high + medium + low === 0) return "Не найдены";
  return `критические ${high} · динамические ${medium} · совпадения ${low}`;
}

function recoveryLabel(value) {
  if (!value || value === "clear") return "Не требовалось";
  const restored = value.match(/restored_.*_index_(\d+)$/);
  if (restored) return `Восстановлен уровень ${restored[1]}`;
  if (value.startsWith("failed_")) return "Восстановление не удалось";
  return value;
}

function csvSet(value) {
  return new Set(String(value || "").split(",").map((item) => item.trim()).filter(Boolean));
}

function compatibilityStateLabel(state) {
  const labels = {
    confirmed: "Подтверждено",
    known_supported: "Разрешено правилом",
    blocked: "Выше OEM-предела",
    rejected: "Отклонено",
    untested: "Не проверено"
  };
  return labels[state] || "Неизвестно";
}

function compatibilityStateClass(state) {
  if (state === "confirmed") return "compat-good";
  if (state === "known_supported" || state === "untested") return "compat-neutral";
  return "compat-bad";
}

function customCompatibilityState(value) {
  if (!Number.isInteger(value)) return "invalid";
  if (compatibility.confirmed.has(String(value))) return "confirmed";
  if (compatibility.knownMax && value > compatibility.knownMax) return "blocked";
  if (compatibility.rejected.has(String(value))) return "rejected";
  if (compatibility.knownMax && value <= compatibility.knownMax) return "known_supported";
  return "untested";
}

function updateCompatibilityProfiles(data) {
  compatibility.knownMax = /^\d+$/.test(String(data.compatKnownMax)) ? Number(data.compatKnownMax) : null;
  compatibility.confirmed = csvSet(data.compatConfirmed);
  compatibility.rejected = csvSet(data.compatRejected);
  compatibility.states = {
    30: data.profile30State,
    50: data.profile50State,
    75: data.profile75State,
    100: data.profile100State
  };
  Object.entries(compatibility.states).forEach(([value, state]) => {
    const button = document.querySelector(`[data-profile="${value}"]`);
    const label = document.querySelector(`[data-profile-state="${value}"]`);
    if (label) {
      label.textContent = compatibilityStateLabel(state);
      label.className = compatibilityStateClass(state);
    }
    if (button) button.disabled = operationInProgress || !hasBridge() || !statusLoaded || (["blocked", "rejected"].includes(state) && String(currentProfile) !== value);
  });
}

function selectedCompatibilityState(profile = selectedProfile, custom = selectedCustomValue()) {
  if (profile === "stock") return "allowed";
  if (profile === "custom") return customCompatibilityState(custom);
  return compatibility.states[String(profile)] || "untested";
}

function applyProfileAvailability() {
  Object.entries(compatibility.states).forEach(([value, state]) => {
    const button = document.querySelector(`[data-profile="${value}"]`);
    if (button) button.disabled = operationInProgress || !hasBridge() || !statusLoaded || (["blocked", "rejected"].includes(state) && String(currentProfile) !== value);
  });
  const stockButton = document.querySelector('[data-profile="stock"]');
  const customButton = document.querySelector('[data-profile="custom"]');
  if (stockButton) stockButton.disabled = operationInProgress || !hasBridge() || !statusLoaded;
  if (customButton) customButton.disabled = operationInProgress || !hasBridge() || !statusLoaded;
}

function selectionKey(profile, custom) {
  return profile === "custom" ? `custom:${custom}` : profile;
}

function selectedCustomValue() {
  const raw = $("customInput").value.trim();
  if (!/^\d+$/.test(raw)) return null;
  const parsed = Number(raw);
  return Number.isInteger(parsed) ? parsed : null;
}

function updateApplyState() {
  const selectedCustom = selectedCustomValue();
  const validCustom = selectedProfile !== "custom" || (Number.isInteger(selectedCustom) && selectedCustom >= 15 && selectedCustom <= 100);
  const unchanged = validCustom && selectionKey(selectedProfile, selectedCustom) === selectionKey(currentProfile, currentCustom);
  const state = selectedCompatibilityState(selectedProfile, selectedCustom);
  const blocked = ["blocked", "rejected"].includes(state);
  const button = $("applyButton");

  button.disabled = operationInProgress || !hasBridge() || !statusLoaded || unchanged || !validCustom || blocked;
  if (operationInProgress) button.textContent = "Выполнение…";
  else if (!hasBridge()) button.textContent = "Системный мост недоступен";
  else if (!statusLoaded) button.textContent = "Состояние не загружено";
  else if (!validCustom) button.textContent = "Введите целое значение 15–100";
  else if (unchanged) button.textContent = "Этот профиль уже выбран";
  else if (state === "blocked") button.textContent = compatibility.knownMax ? `Выше OEM-предела ${compatibility.knownMax}` : "Профиль заблокирован";
  else if (state === "rejected") button.textContent = "Это значение уже отклонено";
  else if (state === "untested") button.textContent = "Сохранить непроверенный профиль";
  else button.textContent = "Сохранить профиль";

  $("pendingSelection").textContent = profileLabel(selectedProfile, selectedCustom);
  let explanation = profileDescriptions[selectedProfile];
  const valueLabel = selectedProfile === "custom" ? selectedCustom : selectedProfile;
  if (!validCustom) explanation += " Укажите целое число без дробной части.";
  else if (state === "blocked") explanation += compatibility.knownMax ? ` Точная прошивка имеет известный предел ${compatibility.knownMax}.` : " Этот профиль заблокирован текущим правилом совместимости.";
  else if (state === "rejected") explanation += " Это значение уже было отклонено AudioService на текущем fingerprint.";
  else if (state === "confirmed") explanation += " Это значение уже подтверждено AudioService на текущем fingerprint.";
  else if (state === "known_supported") explanation += " Значение находится внутри известного предела, но ещё требует runtime-подтверждения.";
  else if (state === "untested" && selectedProfile !== "stock") explanation += ` Данных для значения ${valueLabel} на текущем fingerprint пока нет.`;
  $("profileExplanation").textContent = explanation;
}
function chooseProfile(profile) {
  const target = document.querySelector(`[data-profile="${profile}"]`);
  if (target?.disabled && String(currentProfile) !== String(profile)) return;
  selectedProfile = profile;
  document.querySelectorAll("[data-profile]").forEach((button) => {
    const selected = button.dataset.profile === profile;
    button.classList.toggle("selected", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
  $("customRow").classList.toggle("hidden", profile !== "custom");
  updateApplyState();
}

function restoreControlAvailability() {
  const bridgeAvailable = hasBridge();
  document.querySelectorAll("[data-view-target]").forEach((button) => { button.disabled = operationInProgress; });
  $("refreshButton").disabled = operationInProgress || !bridgeAvailable;
  document.querySelectorAll(".action-grid button").forEach((button) => { button.disabled = operationInProgress || !bridgeAvailable; });
  $("historyButton").disabled = operationInProgress || !bridgeAvailable;
  $("rebootButton").disabled = operationInProgress || !bridgeAvailable;
  applyProfileAvailability();
  updateApplyState();
  setTestControls(testActive, Number($("testCountdown").textContent || 0));
}

function setBusy(busy) {
  operationInProgress = busy;
  document.documentElement.setAttribute("aria-busy", String(busy));
  document.querySelectorAll("button").forEach((button) => {
    button.classList.toggle("busy", busy);
    if (busy) button.disabled = true;
  });
  if (!busy) restoreControlAvailability();
}
function setTestControls(active, remaining = 0) {
  testActive = active;
  document.querySelectorAll("[data-test-percent]").forEach((button) => { button.disabled = !active || operationInProgress || !hasBridge() || !statusLoaded; });
  $("testRestore").disabled = !active || operationInProgress || !hasBridge() || !statusLoaded;
  $("testBegin").disabled = active || operationInProgress || !hasBridge() || !statusLoaded;
  $("testNotice").classList.toggle("hidden", !active);
  clearInterval(countdownTimer);
  countdownTimer = null;
  if (!active) return;
  let left = Math.max(0, Number(remaining || 0));
  $("testCountdown").textContent = String(left);
  if (left === 0) {
    setTimeout(() => refresh({ preserveSelection: true }), 300);
    return;
  }
  countdownTimer = setInterval(() => {
    left = Math.max(0, left - 1);
    $("testCountdown").textContent = String(left);
    if (left === 0) {
      clearInterval(countdownTimer);
      countdownTimer = null;
      setTimeout(() => refresh({ preserveSelection: true }), 800);
    }
  }, 1000);
}

async function refresh({ preserveSelection = false, showConsole = true } = {}) {
  try {
    const { stdout } = await shell(`${CTL} web-status`);
    const data = JSON.parse(stdout.trim());
    statusLoaded = true;
    currentProfile = data.profile;
    currentCustom = Number.isInteger(Number(data.custom)) ? Number(data.custom) : 60;

    $("metricProfile").textContent = profileLabel(data.profile, data.custom);
    $("metricProperty").textContent = propertyLabel(data.property);
    $("metricRange").textContent = rangeLabel(data.audioMin, data.audioMax);
    $("metricBaseline").textContent = baselineLabel(data.baselineState, data.baselineMax);
    $("metricRom").textContent = data.romName || "Не определена";
    $("romName").textContent = data.romVersion && data.romVersion !== "unknown" ? `${data.romName} · ${data.romVersion}` : data.romName;
    $("romConfidence").textContent = romConfidenceLabel(data.romConfidence);
    $("romScope").textContent = data.romScope;
    $("romOutside").textContent = data.romOutside;
    $("romNotice").textContent = data.romNotice;
    $("compatLimit").textContent = /^\d+$/.test(String(data.compatKnownMax)) ? `${data.compatKnownMax} шагов` : "Неизвестен";
    $("compatSource").textContent = data.compatSource === "bundled_static" ? "Встроенный статический анализ точной прошивки" : data.compatSource === "runtime" ? "Проверка AudioService на устройстве" : data.compatSource === "mixed" ? "Статический анализ и проверка AudioService" : "Требуется проверка профилей";
    $("compatStock").textContent = /^\d+$/.test(String(data.compatStockMax)) ? `0–${data.compatStockMax}` : "Не сохранён";
    $("compatConfirmed").textContent = data.compatConfirmed || "Нет";
    $("compatRejected").textContent = data.compatRejected || "Нет";
    $("compatNote").textContent = data.compatNote || "Результаты относятся только к текущему fingerprint прошивки.";
    updateCompatibilityProfiles(data);
    $("currentSelection").textContent = profileLabel(data.profile, data.custom);
    $("rootManager").textContent = data.rootManager;
    $("deviceName").textContent = `${data.model} (${data.device}) · ${data.androidName || `Android ${data.android}`} / API ${data.api}`;
    $("verificationText").textContent = verificationText(data.verification, data);
    $("verificationAction").textContent = verificationAction(data.verification);
    $("backendText").textContent = backendLabel(data.audioBackend, data.audioConfidence);
    $("integrityText").textContent = integrityLabel(data.integrity);
    $("conflictCount").textContent = conflictLabel(data);
    $("testRecovery").textContent = recoveryLabel(data.testRecovery);
    $("statusBadge").textContent = statusTitle(data.verification);
    $("statusBadge").className = `badge ${statusClass(data.verification)}`;
    $("rebootNotice").classList.toggle("hidden", !Boolean(data.pendingReboot));
    $("firmwareNotice").classList.toggle("hidden", !Boolean(data.firmwareChanged));
    $("customInput").value = data.custom || 60;
    if (!preserveSelection) chooseProfile(data.profile); else updateApplyState();
    setTestControls(Boolean(data.testActive), data.testRemaining);
    $("bridgeWarning").classList.add("hidden");
    $("bridgeWarning").textContent = "Системный мост APatch или KernelSU недоступен. Интерфейс можно просмотреть, но управлять модулем нельзя.";
    restoreControlAvailability();
    const compatibility = data.androidSupported ? "Версия Android входит в кодовый диапазон API 33–36." : `Android API ${data.api} не поддерживается этим релизом.`;
    if (showConsole) log(`${statusTitle(data.verification)}\n${verificationText(data.verification, data)}\n${verificationAction(data.verification)}\n${compatibility}\n\nOEM-предел: ${data.compatKnownMax === "unknown" ? "неизвестен" : data.compatKnownMax}\nПодтверждено: ${data.compatConfirmed || "нет"}\nОтклонено: ${data.compatRejected || "нет"}\n\nОболочка: ${data.romName}\n${data.romNotice}`, true);
  } catch (error) {
    statusLoaded = false;
    const bridgeAvailable = hasBridge();
    $("bridgeWarning").textContent = bridgeAvailable
      ? `Системный мост доступен, но состояние модуля получить не удалось: ${error.message}`
      : "Системный мост APatch или KernelSU недоступен. Интерфейс можно просмотреть, но управлять модулем нельзя.";
    $("bridgeWarning").classList.remove("hidden");
    $("statusBadge").textContent = bridgeAvailable ? "Ошибка данных" : "Нет доступа";
    $("statusBadge").className = "badge bad";
    restoreControlAvailability();
    log(`Не удалось получить состояние.
${error.message}`, true);
  }
}

async function runAndLog(command, title, refreshAfter = false) {
  if (operationInProgress) return { ok: false, output: "Операция уже выполняется." };
  try {
    setBusy(true);
    const drawer = $("consoleDrawer");
    if (drawer) drawer.open = true;
    log(`${title}…`, true);
    const { stdout, stderr } = await shell(command);
    const parts = [];
    if (stdout?.trim()) parts.push(stdout.trimEnd());
    if (stderr?.trim()) parts.push(`stderr:
${stderr.trimEnd()}`);
    const output = parts.join("\n\n") || "Операция выполнена.";
    if (refreshAfter) await refresh({ showConsole: false });
    log(output, true);
    return { ok: true, output };
  } catch (error) {
    log(`Ошибка\n${error.message}`, true);
    return { ok: false, output: error.message };
  } finally {
    setBusy(false);
  }
}

document.querySelectorAll("[data-view-target]").forEach((button) => {
  button.addEventListener("click", () => activateView(button.dataset.viewTarget));
  button.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    const tabs = [...document.querySelectorAll("[data-view-target]")];
    const index = tabs.indexOf(button);
    const nextIndex = event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : (index + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length;
    event.preventDefault();
    tabs[nextIndex].focus();
    activateView(tabs[nextIndex].dataset.viewTarget);
  });
});
document.querySelectorAll("[data-profile]").forEach((button) => button.addEventListener("click", () => chooseProfile(button.dataset.profile)));
$("customInput").addEventListener("input", updateApplyState);

$("applyButton").addEventListener("click", async () => {
  let command = `${CTL} set ${selectedProfile}`;
  let selectedValue = selectedProfile;
  if (selectedProfile === "custom") {
    const value = selectedCustomValue();
    if (!Number.isInteger(value) || value < 15 || value > 100) {
      log("Пользовательское значение должно быть целым числом от 15 до 100.", true);
      updateApplyState();
      return;
    }
    selectedValue = String(value);
    command += ` ${value}`;
  }

  const state = selectedCompatibilityState(selectedProfile, selectedProfile === "custom" ? Number(selectedValue) : null);
  if (state === "blocked") {
    log(compatibility.knownMax ? `Профиль ${selectedValue} заблокирован: OEM-предел текущей прошивки — ${compatibility.knownMax}.` : `Профиль ${selectedValue} заблокирован текущим правилом совместимости.`, true);
    updateApplyState();
    return;
  }
  if (state === "rejected") {
    log(`Профиль ${selectedValue} уже был отклонён AudioService на текущем fingerprint.`, true);
    updateApplyState();
    return;
  }
  if (["untested", "known_supported"].includes(state)) {
    const message = state === "known_supported"
      ? `Значение ${selectedValue} разрешено правилом точной прошивки, но ещё не подтверждено AudioService. Сохранить профиль и проверить его после перезагрузки?`
      : `Значение ${selectedValue} ещё не проверялось на этой прошивке. Оно может быть отклонено, после чего потребуется вернуть последний рабочий или штатный профиль. Продолжить?`;
    if (!window.confirm(message)) return;
  }
  await runAndLog(command, "Сохранение выбранного профиля", true);
});

$("refreshButton").addEventListener("click", () => refresh({ preserveSelection: true }));
$("doctorButton").addEventListener("click", () => runAndLog(`${CTL} doctor`, "Диагностика"));
$("selfCheckButton").addEventListener("click", () => runAndLog(`${CTL} check`, "Проверка целостности", true));
$("fixButton").addEventListener("click", () => runAndLog(`${CTL} fix`, "Исправление файлов и конфигурации", true));
$("conflictsButton").addEventListener("click", () => runAndLog(`${CTL} conflicts`, "Проверка источников конфликтов"));
$("baselineButton").addEventListener("click", () => runAndLog(`${CTL} baseline`, "Сохранение штатного диапазона", true));
$("historyButton").addEventListener("click", (event) => {
  event.preventDefault();
  event.stopPropagation();
  void runAndLog(`${CTL} history 40`, "История");
});
$("reportButton").addEventListener("click", async () => {
  const result = await runAndLog(`${CTL} report`, "Подготовка диагностического отчёта");
  if (!result.ok) return;
  if (!navigator.clipboard) {
    log(`${result.output}

Буфер обмена недоступен в этом WebView. Текст можно выделить вручную.`, true);
    return;
  }
  try {
    await navigator.clipboard.writeText(result.output);
    log(`${result.output}

Отчёт скопирован в буфер обмена.`, true);
  } catch (_) {
    log(`${result.output}

Автоматическое копирование недоступно. Текст можно выделить вручную.`, true);
  }
});

$("testBegin").addEventListener("click", () => runAndLog(`${CTL} test begin`, "Запуск безопасного теста", true));
document.querySelectorAll("[data-test-percent]").forEach((button) => button.addEventListener("click", () => runAndLog(`${CTL} test set ${button.dataset.testPercent}`, `Установка тестового уровня ${button.dataset.testPercent}%`)));
$("testRestore").addEventListener("click", () => runAndLog(`${CTL} test restore`, "Восстановление исходной громкости", true));

$("rebootButton").addEventListener("click", async () => {
  if (!window.confirm("Перезагрузить Android сейчас?")) return;
  try { await shell("reboot"); } catch (error) { log(`Не удалось запустить перезагрузку.\n${error.message}`, true); }
});

window.addEventListener("pagehide", () => {
  if (testActive && hasBridge()) {
    void bridgeExec(`${CTL} test restore`).catch(() => { /* boot recovery remains available */ });
  }
});

let initialView = "control";
try { initialView = sessionStorage.getItem("vss-active-view") || "control"; } catch (_) { /* optional */ }
activateView(initialView, { remember: false });
chooseProfile("stock");
setTestControls(false);
restoreControlAvailability();
refresh();
