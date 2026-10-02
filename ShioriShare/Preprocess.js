// Runs in the Safari page when "Save to Shiori" is picked from the share
// sheet: hands the page itself to the extension, so what gets saved is
// what the user sees (logged-in content included). Capped like the Safari
// extension's captures: HTML cut at a tag boundary, text at 1M characters.
var ExtensionPreprocessingJS = {
  run: function (args) {
    var HTML_MAX = 2 * 1024 * 1024;
    var TEXT_MAX = 1024 * 1024;
    var html = document.documentElement ? document.documentElement.outerHTML : '';
    if (html.length > HTML_MAX) {
      var cut = html.lastIndexOf('>', HTML_MAX - 1);
      html = html.slice(0, cut > 0 ? cut + 1 : HTML_MAX);
    }
    var text = document.body ? document.body.innerText : '';
    if (text.length > TEXT_MAX) text = text.slice(0, TEXT_MAX);
    args.completionFunction({ url: document.URL, title: document.title, html: html, text: text });
  },
  finalize: function () {},
};
