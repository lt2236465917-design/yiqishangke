/**
 * School login auto-fill — NOT an AI click-agent.
 * Fills username/password only. Never fills captcha/2FA. Never clicks 登录.
 * Same-page graphic captcha: still fill user/pass, then stop.
 * Second-factor-only page (SMS/TOTP, no password): fill nothing.
 */
async function kegeAutoFill(username, password) {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  if (isSecondFactorOnlyPage()) {
    return { filled: false, halted: true, captchaPresent: true, reason: "second-factor-only" };
  }

  const tabActivated = activateUsernamePasswordTab();
  if (tabActivated) await sleep(250);

  let userInput = null;
  let passInput = null;
  for (let i = 0; i < 4; i += 1) {
    userInput = findUserInput();
    passInput = findPasswordInput();
    if (userInput && passInput) break;
    await sleep(200);
    if (i === 1) activateUsernamePasswordTab();
  }

  if (!userInput || !passInput) {
    return { filled: false, halted: false, captchaPresent: hasGraphicCaptcha(), reason: "login-form-not-found" };
  }

  setNativeValue(userInput, username);
  setNativeValue(passInput, password);

  const captchaPresent = hasGraphicCaptcha();
  return {
    filled: true,
    halted: false,
    captchaPresent,
    tabActivated,
    reason: captchaPresent ? "filled-wait-captcha" : "filled-no-submit"
  };
}

function activateUsernamePasswordTab() {
  const nodes = Array.from(document.querySelectorAll("a, button, li, div, span, [role='tab']"));
  for (const el of nodes) {
    const text = ((el.innerText || el.textContent || "") + "").replace(/\s+/g, "");
    if (text !== "用户名密码" && text !== "账号密码" && text !== "密码登录") continue;
    if (looksLikeLoginButton(el)) continue;
    try { el.click(); } catch (e) {}
    return true;
  }
  return false;
}

function looksLikeLoginButton(el) {
  const text = ((el.innerText || el.textContent || el.value || "") + "").replace(/\s+/g, "");
  return text === "登录" || text === "立即登录" || text === "登入" || text === "Signin" || text === "Login";
}

function isSecondFactorOnlyPage() {
  if (findPasswordInput()) return false;
  const text = document.body ? document.body.innerText : "";
  const hints = ["短信验证码", "动态口令", "二次验证", "扫码登录确认", "请完成安全验证"];
  return hints.some((h) => text.includes(h));
}

function hasGraphicCaptcha() {
  const selectors = [
    'input[placeholder*="验证码"]',
    'input[placeholder*="图形验证"]',
    'input[name*="captcha" i]',
    'input[id*="captcha" i]',
    'input[name*="yzm" i]',
    'input[id*="yzm" i]',
    'input[name*="verifyCode" i]',
    'input[name*="validCode" i]',
    'input[name*="checkCode" i]',
    'img[src*="captcha" i]',
    'img[src*="yzm" i]',
    'img[alt*="验证码"]',
    '.geetest_slider',
    '.geetest_panel',
    '.slider-verify',
    'iframe[src*="recaptcha"]',
    'iframe[src*="captcha"]'
  ];
  for (const sel of selectors) {
    try {
      if (document.querySelector(sel)) return true;
    } catch (e) {}
  }
  const inputs = Array.from(document.querySelectorAll("input"));
  return inputs.some(isCaptchaField);
}

function findUserInput() {
  const selectors = [
    'input[placeholder*="请输入登录名"]',
    'input[placeholder*="登录名"]',
    'input[placeholder*="用户名"]',
    'input[placeholder*="学号"]',
    'input[name="username" i]',
    'input[name="loginName" i]',
    'input[name="loginname" i]',
    'input[name="userid" i]',
    'input[name="account" i]',
    'input[id="username" i]',
    'input[id="loginName" i]',
    'input[id="loginname" i]',
    'input[autocomplete="username"]'
  ];
  for (const sel of selectors) {
    const el = queryFirst(sel);
    if (el && isUsable(el) && !isCaptchaField(el) && el.type !== "password") return el;
  }
  const inputs = Array.from(document.querySelectorAll('input[type="text"], input[type="tel"], input:not([type])'));
  return inputs.find((el) => isUsable(el) && !isCaptchaField(el)) || null;
}

function findPasswordInput() {
  const selectors = [
    'input[type="password"]',
    'input[placeholder*="请输入密码"]',
    'input[placeholder="请输入密码"]',
    'input[name="password" i]',
    'input[id="password" i]',
    'input[autocomplete="current-password"]'
  ];
  for (const sel of selectors) {
    const el = queryFirst(sel);
    if (el && isUsable(el) && !isCaptchaField(el)) return el;
  }
  return null;
}

function queryFirst(sel) {
  try { return document.querySelector(sel); } catch (e) { return null; }
}

function isCaptchaField(el) {
  const blob = [
    el.getAttribute("name") || "",
    el.id || "",
    el.getAttribute("placeholder") || "",
    el.getAttribute("aria-label") || "",
    el.className || ""
  ].join(" ").toLowerCase();
  const keys = ["captcha", "yzm", "verifycode", "validcode", "checkcode", "randcode", "imgcode", "authcode", "验证码", "图形验证"];
  return keys.some((k) => blob.includes(k));
}

function isUsable(el) {
  if (!el || el.disabled) return false;
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  if (el.getAttribute("aria-hidden") === "true") return false;
  return true;
}

function setNativeValue(el, value) {
  el.focus();
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const desc = Object.getOwnPropertyDescriptor(proto, "value");
  if (desc && desc.set) desc.set.call(el, value);
  else el.value = value;
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
  el.dispatchEvent(new Event("blur", { bubbles: true }));
}
