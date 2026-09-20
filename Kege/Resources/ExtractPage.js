/**
 * Extract page HTML + visible text for the school-specific parser.
 * Walks same-origin frameset frames and iframes. Does not read password fields.
 */
function kegeExtractPage() {
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
    html += "\n<!-- frame:" + p.url + " -->\n" + p.html;
    innerText += "\n" + (p.innerText || "");
  });
  return {
    url: best.url || location.href,
    title: best.title || document.title || "",
    html,
    innerText
  };
}
