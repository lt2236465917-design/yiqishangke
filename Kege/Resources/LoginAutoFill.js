/**
 * School login auto-fill — NOT an AI click-agent.
 * Fills username/password fields only. Never clicks submit. Never fills captcha/2FA.
 * If captcha or second-factor UI is present, returns halted=true and fills nothing.
 */
async function kegeAutoFill(username, password) {
  const captcha = detectCaptchaOrSecondFactor();
  if (captcha) {
    return { filled: false, halted: true, reason: captcha };
  }

  const userInput = findUserInput();
  const passInput = findPasswordInput();
  if (!userInput || !passInput) {
    return { filled: false, halted: false, reason: "login-form-not-found" };
  }

  setNativeValue(userInput, username);
  setNativeValue(passInput, password);
  return { filled: true, halted: false, reason: "filled-no-submit" };
}

function detectCaptchaOrSecondFactor() {
  const selectors = [
    'input[name*="captcha" i]',
    'input[id*="captcha" i]',
    'input[name*="yzm" i]',
    'input[id*="yzm" i]',
    'input[name*="verifyCode" i]',
    'input[placeholder*="验证码"]',
    'input[placeholder*="短信"]',
    'input[placeholder*="动态码"]',
    'img[src*="captcha" i]',
    'img[src*="yzm" i]',
    'img[alt*="验证码"]',
    '.geetest_slider',
    '.geetest_panel',
    '#captcha',
    '.slider-verify',
    'iframe[src*="recaptcha"]',
    'iframe[src*="captcha"]'
  ];
  for (const sel of selectors) {
    try {
      if (document.querySelector(sel)) return "captcha-or-2fa-detected";
    } catch (_) {}
  }
  const text = (document.body && document.body.innerText) ? document.body.innerText : "";
  const hints = ["短信验证码", "动态口令", "二次验证", "扫码登录确认", "请完成安全验证", "滑动验证"];
  if (hints.some((h) => text.includes(h))) return "captcha-or-2fa-detected";
  return null;
}

function findUserInput() {
  const selectors = [
    'input[name="username"]',
    'input[name="loginName"]',
    'input[name="userid"]',
    'input[id="username"]',
    'input[id="loginName"]',
    'input[type="text"]',
    'input[type="tel"]',
    'input[autocomplete="username"]'
  ];
  for (const sel of selectors) {
    const el = document.querySelector(sel);
    if (el && isVisible(el) && !isCaptchaField(el)) return el;
  }
  return null;
}

function findPasswordInput() {
  const el = document.querySelector('input[type="password"]');
  if (el && isVisible(el)) return el;
  return null;
}

function isCaptchaField(el) {
  const blob = `${el.name || ""} ${el.id || ""} ${el.placeholder || ""}`.toLowerCase();
  return ["captcha", "yzm", "verify", "code", "验证"].some((k) => blob.includes(k));
}

function isVisible(el) {
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  const rect = el.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}

function setNativeValue(el, value) {
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
  if (setter) setter.call(el, value);
  else el.value = value;
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
}
