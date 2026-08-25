const vscode = require("vscode");
const { execSync, spawn } = require("child_process");
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
  const from = looking();
  const found = from && project(from);
  if (!found) {
    vscode.window.showErrorMessage(
      `BareRuby: no Gemfile at or above ${from || "anywhere this window is open"}, so there is` +
      " no project to watch. Open a file inside one first."
    );
    return;
  }

  const panel = vscode.window.createWebviewPanel(
    "bareruby.machine",
    `BareRuby — ${found.source}`,
    vscode.ViewColumn.Beside,
    { enableScripts: true, retainContextWhenHidden: true }
  );
  panel.webview.html = page(context, `${path.basename(found.root)}/${found.source}`);

  const run = started(context, found);
  feed(run, panel);
  // The other direction: play, hold, step and speed go back as a line of JSON, which is
  // what `watch.rb` reads between one wait and the next.
  panel.webview.onDidReceiveMessage((order) => {
    if (!run.killed) run.stdin.write(`${JSON.stringify(order)}\n`);
  });
  panel.onDidDispose(() => run.kill());
}

// **Where the reader is**, which is a file rather than a folder — any file. Somebody with
// a `Gemfile` in front of them is standing in a project as surely as somebody with a `.rb`
// in front of them, and the folder the window happens to be open at says nothing either
// way: a home directory is not a project.
function looking() {
  const editor = vscode.window.activeTextEditor;
  if (editor) return editor.document.uri.fsPath;

  const folder = (vscode.workspace.workspaceFolders || [])[0];
  return folder && folder.uri.fsPath;
}

// **A project starts where its Gemfile is** — that is what bundler answers, and what every
// verb here reads its record from. What to run is the file in front of the reader when
// that is a program, and what a project is written around when it is not.
function project(from) {
  const root = rooted(fs.statSync(from).isDirectory() ? from : path.dirname(from));
  if (!root) return null;

  const source = from.endsWith(".rb") ? path.relative(root, from) : "app/main.rb";
  return { root, source };
}

function rooted(at) {
  for (;;) {
    if (fs.existsSync(path.join(at, "Gemfile"))) return at;

    const above = path.dirname(at);
    if (above === at) return null;
    at = above;
  }
}

// **No length is given, so the run does not end.** A loop that keeps going is the thing
// being watched; cutting it off after some number of seconds would answer a question
// nobody asked. It stops when the panel is closed, and holds when somebody says so.
function started(context, found) {
  const watcher = path.join(context.extensionPath, "watch.rb");
  return spawn("bundle", ["exec", "ruby", watcher, found.source], {
    cwd: found.root,
    env: { ...process.env, PATH: reachable() }
  });
}

// **`bundle` is usually not a file the editor can find.** A desk that manages its Ruby
// versions puts a shim on the path from a shell profile, and an extension host started
// before any profile was read has none of it — which is `spawn bundle EACCES` rather than
// anything about Ruby.
//
// So the path is asked for once, of the same shell a terminal on this desk would be. The
// shell is interactive because that is the file the profile is usually in; what it says
// about job control on the way is not interesting and is dropped.
let known = null;

function reachable() {
  if (known) return known;

  try {
    const asked = execSync('bash -ic \'printf %s "$PATH"\'', {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    });
    known = asked || process.env.PATH;
  } catch {
    known = process.env.PATH;
  }
  return known;
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
  // Anything the run says on the way out goes to the panel rather than to a log: a blank
  // panel whose reason is somewhere else is the one thing this must not be.
  run.stderr.on("data", (chunk) => panel.webview.postMessage({ trouble: chunk.toString() }));
  run.on("error", (failure) => panel.webview.postMessage({ trouble: failure.message }));
  run.on("close", (status) => {
    if (status) panel.webview.postMessage({ trouble: `\nThe run ended with status ${status}.` });
  });
}

function page(context, program) {
  const file = path.join(context.extensionPath, "media", "panel.html");
  const nonce = String(Math.random()).slice(2);
  return fs
    .readFileSync(file, "utf8")
    .replace(/\{\{nonce\}\}/g, nonce)
    .replace(/\{\{program\}\}/g, program);
}

module.exports = { activate, deactivate() {} };
