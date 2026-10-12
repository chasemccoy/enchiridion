// Runs in Safari's page before the share extension opens. Hands back the page's URL, its title, the selected text and
// its description, the fields the Chrome extension saves too: the selection becomes the record's content and the
// description its summary (ShareInput.from(javaScript:url:text:) in EnchiridionCore). Everything but the two globals
// Safari requires stays inside `run`, so nothing collides with the page's own scripts.
var Preprocess = function () {};

Preprocess.prototype = {
  run: function (args) {
    var selection = "";
    try {
      selection = String(window.getSelection ? window.getSelection() : "");
    } catch (ignored) {
      selection = "";
    }

    // meta[name=description] first (what the Chrome extension reads), then og:description; "" when there is neither.
    var description = "";
    var selectors = ['meta[name="description"]', 'meta[property="og:description"]', 'meta[name="og:description"]'];
    for (var i = 0; i < selectors.length && !description; i++) {
      try {
        var element = document.querySelector(selectors[i]);
        var content = element ? element.getAttribute("content") : "";
        description = content ? String(content).trim() : "";
      } catch (ignored) {
        description = "";
      }
    }

    args.completionFunction({
      url: document.URL,
      title: document.title,
      selection: selection,
      description: description
    });
  },
  finalize: function () {}
};

var ExtensionPreprocessingJS = new Preprocess();
