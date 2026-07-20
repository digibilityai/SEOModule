/**
 * Shared sidebar for offline docs (file:// safe).
 * Each page sets window.DOC_PAGE = "filename" before loading this script.
 */
(function () {
  const page = window.DOC_PAGE || "index.html";
  const prefix = window.DOC_PREFIX || ""; // "" for index, "../" for pages/

  function href(name) {
    if (name === "index.html") return prefix + "index.html";
    return prefix + "pages/" + name;
  }

  function link(name, label) {
    const active = page === name ? ' class="active"' : "";
    return `<a href="${href(name)}"${active}>${label}</a>`;
  }

  const html = `
    <a class="brand" href="${href("index.html")}">
      <strong>SEO Intelligence</strong>
      <span>Architecture &amp; flow docs</span>
    </a>
    <nav class="nav" aria-label="Documentation">
      <div class="nav-section">Start here</div>
      ${link("index.html", "Overview")}
      ${link("architecture.html", "Overall architecture")}
      ${link("status.html", "Current status")}

      <div class="nav-section">Sequences</div>
      ${link("request-flows.html", "Request sequences")}
      ${link("data-flows.html", "Data-flow sequences")}
      ${link("crawler.html", "Crawler pipeline")}
      ${link("ownership.html", "Ownership verification")}

      <div class="nav-section">System map</div>
      ${link("modules.html", "Modules &amp; routes")}
      ${link("database.html", "Tables &amp; RPCs")}
      ${link("service-layer.html", "Service layer")}
      ${link("auth-access.html", "Auth &amp; access")}

      <div class="nav-section">Source docs</div>
      ${link("markdown-index.html", "All markdown files")}
    </nav>
  `;

  const mount = document.getElementById("sidebar");
  if (mount) mount.innerHTML = html;
})();
