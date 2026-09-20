/**
 * Extract page HTML + visible text for the school-specific parser.
 * Does not read password field values.
 */
function kegeExtractPage() {
  const clone = document.documentElement.cloneNode(true);
  clone.querySelectorAll('input[type="password"]').forEach((el) => {
    el.setAttribute("value", "");
    el.value = "";
  });
  const html = clone.outerHTML || "";
  const text = document.body ? document.body.innerText : "";
  return {
    url: location.href,
    title: document.title || "",
    html,
    innerText: text
  };
}
