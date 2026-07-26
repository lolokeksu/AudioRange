let callbackCounter = 0;

function getBridge() {
  return globalThis.ksu || globalThis.apatch || globalThis.kernelSU || globalThis.KernelSU || null;
}

function normalizeResult(result) {
  if (typeof result === "string") return { errno: 0, stdout: result, stderr: "" };
  const value = result || {};
  return {
    errno: Number(value.errno ?? value.code ?? 0),
    stdout: String(value.stdout ?? value.out ?? ""),
    stderr: String(value.stderr ?? value.err ?? "")
  };
}

export function hasBridge() {
  return typeof getBridge()?.exec === "function";
}

export function exec(command, options = {}) {
  const nativeBridge = getBridge();
  if (typeof nativeBridge?.exec !== "function") {
    return Promise.reject(new Error("Системный мост APatch/KernelSU недоступен."));
  }

  // KernelSU and APatch expose the native callback API through window.ksu:
  // ksu.exec(command, JSON.stringify(options), callbackName).
  const callbackStyle = nativeBridge === globalThis.ksu || nativeBridge.exec.length >= 3;
  if (!callbackStyle) {
    try {
      const result = nativeBridge.exec(command, options);
      if (typeof result === "undefined") {
        return Promise.reject(new Error("Системный мост не вернул результат и не объявил callback-интерфейс."));
      }
      return Promise.resolve(result).then(normalizeResult);
    } catch (error) {
      return Promise.reject(error);
    }
  }

  return new Promise((resolve, reject) => {
    const callbackName = `ar_exec_${Date.now()}_${callbackCounter++}`;
    let settled = false;
    const cleanup = () => {
      delete globalThis[callbackName];
      clearTimeout(timeoutId);
    };
    const settle = (handler, value) => {
      if (settled) return;
      settled = true;
      cleanup();
      handler(value);
    };

    globalThis[callbackName] = (errno, stdout, stderr) => {
      settle(resolve, normalizeResult({ errno, stdout, stderr }));
    };

    const timeoutId = setTimeout(() => {
      settle(reject, new Error("Системная команда не завершилась за 120 секунд."));
    }, 120000);

    try {
      nativeBridge.exec(command, JSON.stringify(options), callbackName);
    } catch (error) {
      settle(reject, error);
    }
  });
}
