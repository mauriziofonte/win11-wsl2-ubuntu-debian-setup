// Plays a tape (the VHS tape language, the commands listed below) in a real terminal and writes what the
// terminal shows to an asciicast v2 file, which agg turns into a GIF.
//
//   node docs/tapes/record.mjs docs/tapes/windows-setup.tape docs/media/windows-setup.cast
//
// VHS itself hangs on Windows runners (its ttyd never starts the shell), so the tapes are played here on
// ConPTY through node-pty, with a headless xterm.js keeping the screen that Wait reads.
//
// Commands: Output, Set (Shell, FontSize, Width, Height, Padding, TypingSpeed, WaitTimeout, WaitPattern; the
// others are for the renderer), Hide, Show, Type "text", Enter, Sleep <time>, Wait[+Screen|+Line][@<time>]
// [/regex/]. A Wait that does not match in time stops the recording and prints the screen.
//
// Author: Maurizio Fonte (https://www.mauriziofonte.it)
// License: MIT License

import fs from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const pty = require("node-pty");
const { Terminal } = require("@xterm/headless");
const { SerializeAddon } = require("@xterm/addon-serialize");

const [tapePath, castPath] = process.argv.slice(2);
if (!tapePath || !castPath) {
    console.error("usage: node record.mjs TAPE CAST");
    process.exit(2);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function duration(text) {
    const m = /^(\d+(?:\.\d+)?)(ms|s|m)?$/.exec(text);
    if (!m) throw new Error(`not a duration: ${text}`);
    return Number(m[1]) * { ms: 1, s: 1000, m: 60000 }[m[2] || "s"];
}

function regex(text) {
    const m = /^\/(.*)\/$/.exec(text);
    if (!m) throw new Error(`not a /regex/: ${text}`);
    return new RegExp(m[1]);
}

// The argument of Type: a string in "", '' or `` (no escapes, as in VHS).
function quoted(text) {
    const m = /^(["'`])(.*)\1$/.exec(text);
    if (!m) throw new Error(`not a quoted string: ${text}`);
    return m[2];
}

const commands = fs
    .readFileSync(tapePath, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));

const settings = {
    Shell: "bash", FontSize: 22, Width: 1200, Height: 600, Padding: 60,
    TypingSpeed: 50, WaitTimeout: 15000, WaitPattern: />\s*$/,
};
for (const line of commands) {
    const m = /^Set (\w+) (.+)$/.exec(line);
    if (!m) continue;
    const [, name, value] = m;
    if (["FontSize", "Width", "Height", "Padding"].includes(name)) settings[name] = Number(value);
    else if (["TypingSpeed", "WaitTimeout"].includes(name)) settings[name] = duration(value);
    else if (name === "WaitPattern") settings[name] = regex(value);
    else if (name === "Shell") settings[name] = quoted(value);
}

// The terminal size that the pixel size gives at this font size (the renderer uses the same font size).
const cols = Math.floor((settings.Width - 2 * settings.Padding) / (settings.FontSize * 0.6));
const rows = Math.floor((settings.Height - 2 * settings.Padding) / (settings.FontSize * 1.4));

const shells = {
    powershell: ["powershell.exe", ["-NoLogo", "-NoProfile"]],
    pwsh: ["pwsh.exe", ["-NoLogo", "-NoProfile"]],
    bash: ["bash", ["--norc", "-i"]],
};
const [file, args] = shells[settings.Shell] || [settings.Shell, []];

const term = new Terminal({ cols, rows, scrollback: 2000, allowProposedApi: true });
const serializer = new SerializeAddon();
term.loadAddon(serializer);

const events = [];
const started = Date.now();
let hidden = false;
let hiddenSince = 0;
let hiddenTotal = 0;
const clock = () => (Date.now() - started - hiddenTotal) / 1000;

const shell = pty.spawn(file, args, {
    name: "xterm-256color",
    cols,
    rows,
    cwd: process.cwd(),
    env: { ...process.env, TERM: "xterm-256color" },
});
let exited = false;
shell.onExit(() => { exited = true; });
shell.onData((data) => {
    term.write(data);
    if (!hidden) events.push([clock(), "o", data]);
});

const flush = () => new Promise((resolve) => term.write("", resolve));

// The visible screen, with lines that wrap joined again.
function screenText() {
    const buffer = term.buffer.active;
    const lines = [];
    for (let y = 0; y < term.rows; y++) {
        const line = buffer.getLine(buffer.viewportY + y);
        if (!line) continue;
        const text = line.translateToString(true);
        if (line.isWrapped && lines.length) lines[lines.length - 1] += text;
        else lines.push(text);
    }
    return lines.join("\n");
}

// The line of the cursor, or the last line with text above it.
function lineText() {
    const buffer = term.buffer.active;
    for (let y = buffer.baseY + buffer.cursorY; y >= 0; y--) {
        const text = buffer.getLine(y)?.translateToString(true).trimEnd();
        if (text) return text;
    }
    return "";
}

async function wait(what, timeout, pattern) {
    const deadline = Date.now() + timeout;
    while (true) {
        await flush();
        const text = what === "Screen" ? screenText() : lineText();
        if (pattern.test(text)) return;
        if (exited) throw new Error(`the shell exited while waiting for ${pattern}`);
        if (Date.now() > deadline) throw new Error(`no ${pattern} on the ${what.toLowerCase()} after ${timeout / 1000}s`);
        await sleep(250);
    }
}

async function run() {
    for (const line of commands) {
        const [command, ...rest] = line.split(" ");
        const arg = rest.join(" ");
        const waitCommand = /^Wait(?:\+(Screen|Line))?(?:@(\S+))?$/.exec(command);
        if (command === "Output" || command === "Set") continue;
        else if (command === "Hide") {
            hidden = true;
            hiddenSince = Date.now();
        }
        else if (command === "Show") {
            await flush();
            hiddenTotal += Date.now() - hiddenSince;
            hidden = false;
            // The screen as it is now replaces what the recording skipped.
            const buffer = term.buffer.active;
            const screen = serializer.serialize({ scrollback: 0 });
            events.push([clock(), "o", `\x1b[H\x1b[2J${screen}\x1b[${buffer.cursorY + 1};${buffer.cursorX + 1}H`]);
        }
        else if (command === "Type") {
            for (const ch of quoted(arg)) {
                shell.write(ch);
                await sleep(settings.TypingSpeed);
            }
        }
        else if (command === "Enter") shell.write("\r");
        else if (command === "Sleep") await sleep(duration(arg));
        else if (waitCommand) {
            const what = waitCommand[1] || "Line";
            const timeout = waitCommand[2] ? duration(waitCommand[2]) : settings.WaitTimeout;
            await wait(what, timeout, arg ? regex(arg) : settings.WaitPattern);
        }
        else throw new Error(`unknown command: ${line}`);
        console.log(`${clock().toFixed(1).padStart(7)}s ${hidden ? "(hidden) " : ""}${line}`);
    }
}

function save() {
    const header = { version: 2, width: cols, height: rows, timestamp: Math.floor(started / 1000), env: { TERM: "xterm-256color" } };
    const lines = [JSON.stringify(header), ...events.map(([t, type, data]) => JSON.stringify([Number(t.toFixed(6)), type, data]))];
    fs.writeFileSync(castPath, lines.join("\n") + "\n");
}

let status = 0;
try {
    await run();
    await flush();
}
catch (error) {
    status = 1;
    console.error(`FAILED: ${error.message}`);
    console.error("--- the screen:");
    console.error(screenText());
}
save();
shell.kill();
process.exit(status);
