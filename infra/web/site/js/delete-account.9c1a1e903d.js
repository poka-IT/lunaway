// Account deletion with a recovery code (lunaway.net/account/delete).
//
// The page carries every message in the HTML of each of its languages; this file
// only decides which one to show. It sends one GraphQL mutation,
// deleteAccountWithRecoveryCode, to the endpoint named by the form's
// data-endpoint attribute, and stores nothing in the browser.
//
// The code is checked here first, with the rules of
// backend/crates/lunaway-auth/src/recovery.rs (alphabet, length, check
// symbol): the server allows 5 recovery attempts an hour per connection, and
// a typo should not spend one.
"use strict";

(function () {
  const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  const DATA_SYMBOLS = 26;
  const MAX_INPUT_CHARS = 100;
  const MUTATION =
    "mutation DeleteAccount($code: String!) { deleteAccountWithRecoveryCode(code: $code) }";

  const form = document.getElementById("delete-form");
  if (!form || !window.fetch) {
    return;
  }
  const endpoint = form.getAttribute("data-endpoint");
  const fieldset = form.querySelector("fieldset");
  const input = document.getElementById("recovery-code");
  const confirmBox = document.getElementById("delete-confirm");
  const echo = document.getElementById("code-echo");
  const confirmButton = document.getElementById("delete-go");
  const backButton = document.getElementById("delete-back");
  const status = document.getElementById("delete-status");
  const errors = form.querySelectorAll("[data-error]");
  const results = document.querySelectorAll("[data-result]");

  let pending = null;

  function symbolValue(c) {
    // ASCII upper case only, as the server does (to_ascii_uppercase).
    let u = c >= "a" && c <= "z" ? c.toUpperCase() : c;
    if (u === "O") {
      u = "0";
    } else if (u === "I" || u === "L") {
      u = "1";
    }
    return u.length === 1 ? ALPHABET.indexOf(u) : -1;
  }

  // Luhn mod 32: the rightmost data symbol is doubled.
  function checkValue(symbols) {
    let sum = 0;
    for (let i = 0; i < symbols.length; i += 1) {
      const v = symbols[symbols.length - 1 - i];
      const addend = v * (i % 2 === 0 ? 2 : 1);
      sum += Math.floor(addend / 32) + (addend % 32);
    }
    return (32 - (sum % 32)) % 32;
  }

  function parse(text) {
    const chars = Array.from(text);
    const symbols = [];
    for (const c of chars) {
      if (/\s/.test(c) || c === "-") {
        continue;
      }
      const v = symbolValue(c);
      if (v < 0) {
        return { error: "char", char: c };
      }
      symbols.push(v);
    }
    if (symbols.length === 0) {
      return { error: "empty" };
    }
    if (symbols.length !== DATA_SYMBOLS + 1 || chars.length > MAX_INPUT_CHARS) {
      return { error: "length", count: symbols.length };
    }
    const data = symbols.slice(0, DATA_SYMBOLS);
    if (checkValue(data) !== symbols[DATA_SYMBOLS] || data[0] >= 8) {
      return { error: "typo" };
    }
    return { code: symbols.map((v) => ALPHABET[v]).join("") };
  }

  function grouped(code) {
    return code.match(/.{1,4}/g).join("-");
  }

  function fill(root, slot, value) {
    root.querySelectorAll('[data-slot="' + slot + '"]').forEach((el) => {
      el.textContent = value;
    });
  }

  function showError(kind, detail) {
    let shown = null;
    errors.forEach((el) => {
      const match = el.getAttribute("data-error") === kind;
      el.hidden = !match;
      if (match) {
        shown = el;
      }
    });
    if (shown) {
      if (detail !== undefined) {
        fill(shown, kind === "char" ? "char" : "count", String(detail));
      }
      input.setAttribute("aria-invalid", "true");
      input.setAttribute("aria-describedby", "recovery-hint " + shown.id);
    }
  }

  function clearError() {
    errors.forEach((el) => {
      el.hidden = true;
    });
    input.removeAttribute("aria-invalid");
    input.setAttribute("aria-describedby", "recovery-hint");
  }

  function showResult(kind, minutes) {
    let shown = null;
    results.forEach((el) => {
      const match = el.getAttribute("data-result") === kind;
      el.hidden = !match;
      if (match) {
        shown = el;
      }
    });
    if (shown) {
      if (minutes !== undefined) {
        fill(shown, "minutes", String(minutes));
      }
      const heading = shown.querySelector("h2, h3");
      if (heading) {
        heading.setAttribute("tabindex", "-1");
        heading.focus();
      }
    }
  }

  function hideResults() {
    results.forEach((el) => {
      el.hidden = true;
    });
  }

  function backToForm() {
    pending = null;
    confirmBox.hidden = true;
    form.hidden = false;
    status.textContent = "";
    input.focus();
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    hideResults();
    const parsed = parse(input.value);
    if (parsed.error) {
      showError(parsed.error, parsed.error === "char" ? parsed.char : parsed.count);
      input.focus();
      return;
    }
    clearError();
    pending = parsed.code;
    echo.textContent = grouped(parsed.code);
    form.hidden = true;
    confirmBox.hidden = false;
    const heading = confirmBox.querySelector("h2, h3");
    heading.setAttribute("tabindex", "-1");
    heading.focus();
  });

  input.addEventListener("input", () => {
    if (input.getAttribute("aria-invalid")) {
      clearError();
    }
  });

  backButton.addEventListener("click", backToForm);

  confirmButton.addEventListener("click", async () => {
    if (!pending) {
      backToForm();
      return;
    }
    const code = pending;
    confirmButton.disabled = true;
    backButton.disabled = true;
    status.textContent = status.getAttribute("data-sending");
    let outcome;
    let minutes;
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        mode: "cors",
        credentials: "omit",
        cache: "no-store",
        referrerPolicy: "no-referrer",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: MUTATION,
          operationName: "DeleteAccount",
          variables: { code: code },
        }),
      });
      let body = null;
      try {
        body = await response.json();
      } catch (_) {
        body = null;
      }
      const error = body && Array.isArray(body.errors) ? body.errors[0] : null;
      const errorCode = error && error.extensions ? error.extensions.code : null;
      const deleted = body && body.data ? body.data.deleteAccountWithRecoveryCode : null;
      if (response.status === 429 || errorCode === "RATE_LIMITED") {
        const fromBody = error && error.extensions ? Number(error.extensions.retryAfterSeconds) : NaN;
        const fromHeader = Number(response.headers.get("Retry-After"));
        const seconds = fromBody > 0 ? fromBody : fromHeader > 0 ? fromHeader : 3600;
        outcome = "limited";
        minutes = Math.max(1, Math.ceil(seconds / 60));
      } else if (response.ok && deleted === true) {
        outcome = "deleted";
      } else if (errorCode === "NOT_FOUND" || (response.ok && deleted === false)) {
        outcome = "not-found";
      } else if (errorCode === "INVALID_INPUT") {
        outcome = "invalid";
      } else {
        outcome = "unknown";
      }
    } catch (_) {
      outcome = "unknown";
    }
    pending = null;
    status.textContent = "";
    confirmButton.disabled = false;
    backButton.disabled = false;
    confirmBox.hidden = true;
    if (outcome === "deleted") {
      input.value = "";
      form.hidden = true;
    } else {
      form.hidden = false;
    }
    showResult(outcome, minutes);
  });

  fieldset.disabled = false;
  const noScript = document.getElementById("delete-noscript");
  if (noScript) {
    noScript.hidden = true;
  }
})();
