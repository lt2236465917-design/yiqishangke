import Foundation

enum EmbeddedScripts {
    static let autoFill = """
    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    const looksLikeLoginButton = (el) => {
      const text = ((el.innerText || el.textContent || el.value || "") + "").replace(/\\s+/g, "");
      return text === "登录" || text === "立即登录" || text === "登入" || text === "Signin" || text === "Login";
    };

    const isCaptchaField = (el) => {
      const blob = [
        el.getAttribute("name") || "",
        el.id || "",
        el.getAttribute("placeholder") || "",
        el.getAttribute("aria-label") || "",
        el.className || ""
      ].join(" ").toLowerCase();
      const keys = ["captcha", "yzm", "verifycode", "validcode", "checkcode", "randcode", "imgcode", "authcode", "验证码", "图形验证"];
      return keys.some((k) => blob.includes(k));
    };

    const isUsable = (el) => {
      if (!el || el.disabled) return false;
      const style = window.getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") return false;
      if (el.getAttribute("aria-hidden") === "true") return false;
      return true;
    };

    const queryFirst = (sel) => {
      try { return document.querySelector(sel); } catch (e) { return null; }
    };

    const findUserInput = () => {
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
    };

    const findPasswordInput = () => {
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
    };

    const hasGraphicCaptcha = () => {
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
        try { if (document.querySelector(sel)) return true; } catch (e) {}
      }
      return Array.from(document.querySelectorAll("input")).some(isCaptchaField);
    };

    const activateUsernamePasswordTab = () => {
      const nodes = Array.from(document.querySelectorAll("a, button, li, div, span, [role='tab']"));
      for (const el of nodes) {
        const text = ((el.innerText || el.textContent || "") + "").replace(/\\s+/g, "");
        if (text !== "用户名密码" && text !== "账号密码" && text !== "密码登录") continue;
        if (looksLikeLoginButton(el)) continue;
        try { el.click(); } catch (e) {}
        return true;
      }
      return false;
    };

    const setNativeValue = (el, value) => {
      el.focus();
      const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const desc = Object.getOwnPropertyDescriptor(proto, "value");
      if (desc && desc.set) desc.set.call(el, value);
      else el.value = value;
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
      el.dispatchEvent(new Event("blur", { bubbles: true }));
    };

    if (!findPasswordInput()) {
      const bodyText = document.body ? document.body.innerText : "";
      const secondHints = ["短信验证码", "动态口令", "二次验证", "扫码登录确认"];
      if (secondHints.some((h) => bodyText.includes(h))) {
        return { filled: false, halted: true, captchaPresent: true, reason: "second-factor-only" };
      }
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
    """

    static let extractPage = """
    (function() {
      const seen = [];
      const pieces = [];
      const scoreOf = (url, title, text, html) => {
        const blob = (url || "") + (title || "") + (text || "") + (html || "");
        let n = 0;
        if (blob.indexOf("课程编号") !== -1 && blob.indexOf("课程名称") !== -1) n += 8;
        if (blob.indexOf("上课时间") !== -1) n += 4;
        if (blob.indexOf("新学期课表") !== -1 || blob.indexOf("我的课表") !== -1) n += 3;
        if (blob.indexOf("周一") !== -1 && (blob.indexOf("上午课") !== -1 || blob.indexOf("下午课") !== -1)) n += 10;
        return n;
      };
      const read = (win) => {
        const piece = { url: "", title: "", html: "", innerText: "", score: 0 };
        try {
          piece.url = win.location.href;
          if (seen.indexOf(piece.url) !== -1) return;
          seen.push(piece.url);
          const doc = win.document;
          piece.title = doc.title || "";
          const clone = doc.documentElement ? doc.documentElement.cloneNode(true) : null;
          if (clone) {
            clone.querySelectorAll('input[type="password"]').forEach((el) => {
              el.setAttribute("value", "");
              el.value = "";
            });
            piece.html = clone.outerHTML || "";
          }
          piece.innerText = doc.body ? doc.body.innerText : "";
          piece.score = scoreOf(piece.url, piece.title, piece.innerText, piece.html);
          pieces.push(piece);
          const kids = [];
          try {
            for (let i = 0; i < win.frames.length; i += 1) kids.push(win.frames[i]);
          } catch (e) {}
          try {
            doc.querySelectorAll("iframe, frame").forEach((el) => {
              try { if (el.contentWindow) kids.push(el.contentWindow); } catch (e2) {}
            });
          } catch (e) {}
          kids.forEach((child) => {
            try { read(child); } catch (e) {}
          });
        } catch (e) {}
      };
      read(window);
      let best = pieces[0] || { url: location.href, title: document.title || "", html: "", innerText: "", score: 0 };
      pieces.forEach((p) => { if (p.score > best.score) best = p; });
      let html = "";
      let innerText = "";
      pieces.forEach((p) => {
        if (!p.html) return;
        html += "\\n<!-- frame:" + p.url + " -->\\n" + p.html;
        innerText += "\\n" + (p.innerText || "");
      });
      return {
        url: best.url || location.href,
        title: best.title || document.title || "",
        html,
        innerText
      };
    })();
    """

    /// Click left-nav 「我的课表」 inside the graduate frameset. Never clicks 登录.
    static let openMyTimetable = """
    (function() {
      const seen = [];
      const forbidden = /登录|立即登录|退出|注销/;
      const result = { clicked: false, text: "", href: "", frameUrl: "" };
      const labelOf = (el) => ((el.innerText || el.textContent || "") + "").replace(/\\s+/g, "");
      const tryClick = (el, win) => {
        const text = labelOf(el);
        if (!text || forbidden.test(text)) return false;
        try { el.click(); } catch (e) { return false; }
        result.clicked = true;
        result.text = text;
        result.href = el.href || el.getAttribute("href") || "";
        result.frameUrl = win.location.href;
        return true;
      };
      const walk = (win) => {
        try {
          const url = win.location.href;
          if (seen.indexOf(url) !== -1) return false;
          seen.push(url);
          const doc = win.document;
          const nodes = Array.from(doc.querySelectorAll("a, button, td, li, span, div, font, u"));
          for (const el of nodes) {
            if (labelOf(el) === "我的课表" && tryClick(el, win)) return true;
          }
          for (const el of nodes) {
            const text = labelOf(el);
            if (text.length > 12) continue;
            if ((text === "课表" || text.indexOf("我的课表") !== -1) && tryClick(el, win)) return true;
          }
          const links = Array.from(doc.querySelectorAll("a[href]"));
          for (const a of links) {
            const href = a.getAttribute("href") || "";
            const text = labelOf(a);
            if (forbidden.test(text)) continue;
            const looks = href.indexOf("课表") !== -1 || /wdkb|xskb|kbcx|courseTable|timetable/i.test(href);
            if (looks && (text.indexOf("课表") !== -1 || href.indexOf("课表") !== -1) && tryClick(a, win)) return true;
          }
          const kids = [];
          try {
            for (let i = 0; i < win.frames.length; i += 1) kids.push(win.frames[i]);
          } catch (e) {}
          try {
            doc.querySelectorAll("iframe, frame").forEach((el) => {
              try { if (el.contentWindow) kids.push(el.contentWindow); } catch (e2) {}
            });
          } catch (e) {}
          for (const child of kids) {
            try { if (walk(child)) return true; } catch (e) {}
          }
        } catch (e) {}
        return false;
      };
      walk(window);
      return result;
    })();
    """

    /// Trigger the portal app tile so IAM can run SSO. Never clicks 登录. Never opens naked frameset.
    static let openGraduateTile = """
    (function() {
      const forbidden = /登录|立即登录|退出|注销/;
      const result = { clicked: false, text: "", href: "", method: "" };
      const labelOf = (el) => ((el.innerText || el.textContent || "") + "").replace(/\\s+/g, "");
      const attrURL = (el) => el.href || el.getAttribute("href") || el.getAttribute("data-url") || el.getAttribute("data-href") || el.getAttribute("data-link") || "";
      const looksSSO = (u) => {
        if (!u || u.indexOf("javascript:") === 0) return false;
        const s = String(u).toLowerCase();
        if (s.indexOf("frameset.jsp") !== -1 && s.indexOf("?") === -1) return false;
        return s.indexOf("oauth") !== -1 || s.indexOf("authorize") !== -1 || s.indexOf("/cas") !== -1 || s.indexOf("sso") !== -1 || s.indexOf("ticket=") !== -1 || s.indexOf("saml") !== -1 || (s.indexOf("wxt.zgysyjy.org.cn") !== -1 && s.indexOf("?") !== -1);
      };
      const origOpen = window.open;
      window.open = function(url) {
        if (url) result.href = String(url);
        result.method = "window.open";
        try { return origOpen.apply(window, arguments); } catch (e) { return null; }
      };
      const fire = (el) => {
        try {
          el.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, view: window }));
          el.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true, view: window }));
          el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
          el.click();
          return true;
        } catch (e) { return false; }
      };
      const nodes = Array.from(document.querySelectorAll("a, button, li, div, span, section, p, h1, h2, h3, h4, [role='button'], [class*='app'], [class*='tile']"));
      const tiles = nodes.filter((el) => {
        const text = labelOf(el);
        if (!text || text.length > 36 || forbidden.test(text)) return false;
        return text.indexOf("研究生综合管理") !== -1;
      }).sort((a, b) => labelOf(a).length - labelOf(b).length);
      for (const el of tiles) {
        const href = attrURL(el);
        if (looksSSO(href)) result.href = href;
        if (fire(el)) {
          result.clicked = true;
          result.text = labelOf(el);
          result.method = result.method || "click";
          break;
        }
      }
      if (!result.href) {
        const html = document.documentElement ? document.documentElement.innerHTML : "";
        const idx = html.indexOf("研究生综合管理");
        const slice = idx === -1 ? html : html.slice(Math.max(0, idx - 500), idx + 900);
        const found = slice.match(/https?:\\/\\/[^\\s"'<>]+/g) || [];
        for (const u of found) {
          if (looksSSO(u)) { result.href = u; result.method = result.method || "scan"; break; }
        }
      }
      window.open = origOpen;
      return result;
    })();
    """

    static let detectGraduateLoginWall = """
    (function() {
      const t = ((document.body && document.body.innerText) || "") + (document.title || "");
      return {
        loginWall: t.indexOf("请登录") !== -1 || t.indexOf("数据处理出现错误") !== -1,
        excerpt: t.replace(/\\s+/g, " ").slice(0, 80)
      };
    })();
    """

    /// Logged-in IAM personal/welcome page — not the application list.
    static let detectIAMSession = """
    (function() {
      const t = ((document.body && document.body.innerText) || "") + (document.title || "");
      const href = String(location.href);
      const hasPassword = !!document.querySelector('input[type="password"]');
      return {
        href: href,
        welcome: t.indexOf("欢迎您") !== -1 || t.indexOf("欢迎你") !== -1,
        logout: t.indexOf("安全退出") !== -1 || t.indexOf("退出登录") !== -1 || t.indexOf("注销") !== -1 || t.indexOf("退出") !== -1,
        loginForm: hasPassword,
        hasAppListHash: /applist|app-list/i.test(href),
        excerpt: t.replace(/\\s+/g, " ").slice(0, 80)
      };
    })();
    """

    /// Hash SPA: switch portal from user-center/welcome to #/appList. Never opens frameset.
    static let goToAppList = """
    (function() {
      const targetHash = "#/appList";
      const target = "https://iam.zgysyjy.org.cn/portal/#/appList";
      const hrefNow = String(location.href);
      if (/applist|app-list/i.test(hrefNow)) {
        return { method: "already", href: hrefNow };
      }
      const clickNav = () => {
        const nodes = Array.from(document.querySelectorAll("a, button, li, span, div, [role='menuitem'], [role='tab']"));
        for (const el of nodes) {
          const t = ((el.innerText || el.textContent || "") + "").replace(/\\s+/g, "");
          if (!t || t.length > 16) continue;
          if (t === "应用列表" || t === "我的应用" || t === "应用中心" || t.indexOf("应用列表") !== -1) {
            try { el.click(); return true; } catch (e) {}
          }
        }
        return false;
      };
      let method = "";
      try { if (clickNav()) method = "nav-click"; } catch (e) {}
      try {
        location.hash = targetHash;
        method = method || "hash";
      } catch (e2) {}
      try {
        history.replaceState(null, "", "/portal/" + targetHash);
        window.dispatchEvent(new HashChangeEvent("hashchange"));
        window.dispatchEvent(new PopStateEvent("popstate"));
        method = method || "replaceState";
      } catch (e3) {}
      if (!/applist|app-list/i.test(String(location.href))) {
        try { location.assign(target); method = "assign"; } catch (e4) {
          location.href = target;
          method = "href";
        }
      }
      return { method: method, href: String(location.href) };
    })();
    """
}
