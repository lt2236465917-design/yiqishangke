import Foundation

enum EmbeddedScripts {
    static let autoFill = """
    const captcha = (() => {
      const selectors = [
        'input[name*="captcha" i]', 'input[id*="captcha" i]',
        'input[name*="yzm" i]', 'input[id*="yzm" i]',
        'input[name*="verifyCode" i]', 'input[placeholder*="验证码"]',
        'input[placeholder*="短信"]', 'input[placeholder*="动态码"]',
        'img[src*="captcha" i]', 'img[src*="yzm" i]', 'img[alt*="验证码"]',
        '.geetest_slider', '.geetest_panel', '#captcha', '.slider-verify',
        'iframe[src*="recaptcha"]', 'iframe[src*="captcha"]'
      ];
      for (const sel of selectors) {
        try { if (document.querySelector(sel)) return "captcha-or-2fa-detected"; } catch (e) {}
      }
      const text = document.body ? document.body.innerText : "";
      const hints = ["短信验证码", "动态口令", "二次验证", "扫码登录确认", "请完成安全验证", "滑动验证"];
      if (hints.some((h) => text.includes(h))) return "captcha-or-2fa-detected";
      return null;
    })();
    if (captcha) {
      return { filled: false, halted: true, reason: captcha };
    }
    const isVisible = (el) => {
      const style = window.getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") return false;
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };
    const isCaptchaField = (el) => {
      const blob = `${el.name || ""} ${el.id || ""} ${el.placeholder || ""}`.toLowerCase();
      return ["captcha", "yzm", "verify", "code", "验证"].some((k) => blob.includes(k));
    };
    const setNativeValue = (el, value) => {
      const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, "value") && Object.getOwnPropertyDescriptor(proto, "value").set;
      if (setter) setter.call(el, value); else el.value = value;
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    };
    let userInput = null;
    const userSelectors = [
      'input[name="username"]', 'input[name="loginName"]', 'input[name="userid"]',
      'input[id="username"]', 'input[id="loginName"]',
      'input[autocomplete="username"]', 'input[type="text"]', 'input[type="tel"]'
    ];
    for (const sel of userSelectors) {
      const el = document.querySelector(sel);
      if (el && isVisible(el) && !isCaptchaField(el)) { userInput = el; break; }
    }
    const passInput = document.querySelector('input[type="password"]');
    if (!userInput || !passInput || !isVisible(passInput)) {
      return { filled: false, halted: false, reason: "login-form-not-found" };
    }
    setNativeValue(userInput, username);
    setNativeValue(passInput, password);
    return { filled: true, halted: false, reason: "filled-no-submit" };
    """

    static let extractPage = """
    (function() {
      const clone = document.documentElement.cloneNode(true);
      clone.querySelectorAll('input[type="password"]').forEach((el) => {
        el.setAttribute("value", "");
        el.value = "";
      });
      return {
        url: location.href,
        title: document.title || "",
        html: clone.outerHTML || "",
        innerText: document.body ? document.body.innerText : ""
      };
    })();
    """
}
