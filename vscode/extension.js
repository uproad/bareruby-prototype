const vscode = require("vscode");
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

// The whole of what this side does: start `watch.rb` on the program in front of the
// reader, and hand every line it writes to a panel. The Ruby half decides what a frame
// is; this one decides nothing about the machine at all.
function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("bareruby.visualize", () => watch(context))
  );
}

function watch(context) {
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  if (!folder) {
    vscode.window.showErrorMessage("BareRuby: open the repository first.");
    return;
  }
  const root = folder.uri.fsPath;
  const source = watched(root);

  const panel = vscode.window.createWebviewPanel(
    "bareruby.machine",
    `BareRuby — ${source}`,
    vscode.ViewColumn.Beside,
    { enableScripts: true, retainContextWhenHidden: true }
  );
  panel.webview.html = page(context);

  const seconds = vscode.workspace.getConfiguration("bareruby").get("seconds", 3);
  const run = spawn("ruby", ["vscode/watch.rb", source, String(seconds)], { cwd: root });
  feed(run, panel);
  panel.onDidDispose(() => run.kill());
}

// The program the reader is looking at, if it is one; the blink otherwise. A path
// relative to the root is what `watch.rb` takes, because that is what every verb takes.
function watched(root) {
  const editor = vscode.window.activeTextEditor;
  if (editor && editor.document.uri.fsPath.endsWith(".rb")) {
    return path.relative(root, editor.document.uri.fsPath);
  }
  return "samples/blink.rb";
}

// One line is one frame. A read can end mid-line, so what is left over waits for the
// rest of itself rather than being parsed as though it were whole.
function feed(run, panel) {
  let rest = "";
  run.stdout.on("data", (chunk) => {
    const lines = (rest + chunk.toString()).split("\n");
    rest = lines.pop();
    for (const line of lines) {
      if (line.length > 0) panel.webview.postMessage(JSON.parse(line));
    }
  });
  run.stderr.on("data", (chunk) => console.error(chunk.toString()));
  run.on("error", (failure) =>
    vscode.window.showErrorMessage(`BareRuby: ${failure.message}`)
  );
}

function page(context) {
  const file = path.join(context.extensionPath, "media", "panel.html");
  const nonce = String(Math.random()).slice(2);
  return fs.readFileSync(file, "utf8").replace(/\{\{nonce\}\}/g, nonce);
}

module.exports = { activate, deactivate() {} };
