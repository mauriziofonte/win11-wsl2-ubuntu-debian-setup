#!/usr/bin/env python3
"""Static checks of the documents against the installers, against each other, and against Gash.

    python3 tests/check-docs.py                      # this repository only
    GASH_REPO=../gash python3 tests/check-docs.py    # also the links into Gash and every `gash` command shown

What it checks:
  * the options tables of the guides match the options lamp-lapp-stack.sh parses and prints in --help;
    the options table of the README matches the parameters of win11.ps1 and of its bootstrap
  * one version, one PHP list, one PHP extension list, one MariaDB series and one PostgreSQL default
    across the scripts, the guides, the README and tests/verify-stack.sh
  * the English and Italian guides have the same sections, the same commands (comments may differ),
    the same CI-run blocks, the same tables and the same external links
  * every relative link and every anchor resolves; links into the Gash repository resolve in GASH_REPO
  * every `gash ...` command in the documents exists in Gash's reference, with the flags used
  * install.ps1 is ASCII without a BOM; win11.ps1 carries the UTF-8 BOM that PowerShell 5.1 needs
  * confs/vscode.json is valid JSON without placeholders

Exit status 1 when a check fails.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
GUIDES = {"en": ROOT / "docs/en/SETUP-EN.md", "it": ROOT / "docs/it/SETUP-IT.md"}
STACK = ROOT / "install/lamp-lapp-stack.sh"
WIN11 = ROOT / "install/win11.ps1"
BOOT = ROOT / "install/install.ps1"
VERIFY = ROOT / "tests/verify-stack.sh"
VSCODE = ROOT / "confs/vscode.json"
DOCS = [README, GUIDES["en"], GUIDES["it"], ROOT / "tests/README.md", ROOT / "AGENTS.md", ROOT / "docs/tapes/README.md"]
GASH = Path(os.environ["GASH_REPO"]).resolve() if os.environ.get("GASH_REPO") else None
THIS_REPO = "https://github.com/mauriziofonte/win11-wsl2-ubuntu-debian-setup"
GASH_REPO_URL = "https://github.com/mauriziofonte/gash"
# Gash functions and aliases that the documents name in prose.
GASH_NAMES = ["wex", "wtm", "wr", "wslc", "php_detect_version", "composer-self-update"]

failures = []


def ok(msg):
    print(f"ok - {msg}")


def fail(msg, detail=""):
    failures.append(msg)
    print(f"not ok - {msg}")
    for line in str(detail).splitlines()[:30]:
        print(f"#   {line}")


def expect_equal(msg, want, got):
    if want == got:
        ok(msg)
    else:
        fail(msg, f"expected: {want}\ngot:      {got}")


def read(path):
    return path.read_text(encoding="utf-8-sig")


def shell_var(text, name):
    m = re.search(rf'^\s*{name}="([^"]*)"', text, re.M)
    if not m:
        fail(f"{name} is defined")
        return ""
    return m.group(1)


# ------------------------------------------------------------------------------------------------
# Markdown helpers

FENCE = re.compile(r"^```(\S*)\s*$")


def code_blocks(text):
    """[(lang, content, ci_name)] for every fenced block; ci_name is set by a <!-- ci:run NAME --> line."""
    blocks, lines, i, pending = [], text.splitlines(), 0, None
    while i < len(lines):
        m = re.match(r"^<!-- ci:run (\S+) -->$", lines[i])
        if m:
            pending = m.group(1)
            i += 1
            continue
        m = FENCE.match(lines[i])
        if m:
            lang, body = m.group(1), []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(lines[i])
                i += 1
            blocks.append((lang, "\n".join(body), pending))
            pending = None
        elif lines[i].strip():
            pending = None
        i += 1
    return blocks


def without_code(text):
    return re.sub(r"^```.*?^```", "", text, flags=re.S | re.M)


def inline_code(text):
    return re.findall(r"`([^`\n]+)`", without_code(text))


def headings(text):
    return [(len(m.group(1)), m.group(2).strip()) for m in re.finditer(r"^(#{1,6}) (.+)$", without_code(text), re.M)]


def slug(title, seen):
    s = title.strip().lower()
    s = re.sub(r"[^\w\- ]", "", s)
    s = s.replace(" ", "-")
    base, n = s, seen.get(s, 0)
    seen[base] = n + 1
    return base if n == 0 else f"{base}-{n}"


def anchors(path):
    seen = {}
    return {slug(t, seen) for _, t in headings(read(path))}


def tables(text):
    """Each table as a list of rows (lists of cells), header and separator excluded."""
    out, cur = [], None
    for line in without_code(text).splitlines():
        if line.startswith("|"):
            cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
            if cur is None:
                cur = {"header": cells, "rows": []}
            elif all(re.fullmatch(r":?-+:?", c) for c in cells):
                continue
            else:
                cur["rows"].append(cells)
        elif cur is not None:
            out.append(cur)
            cur = None
    if cur is not None:
        out.append(cur)
    return out


def links(text):
    found = re.findall(r"\]\(([^)\s]+)\)", without_code(text))
    found += re.findall(r"<(https?://[^>]+)>", without_code(text))
    return found


def strip_comments(lang, body):
    out = []
    for line in body.splitlines():
        if lang in ("bash", "powershell", "ini", "sh"):
            if line.strip().startswith("#"):
                continue
            line = re.sub(r"\s+#\s.*$", "", line)
        out.append(line.rstrip())
    return "\n".join(out)


# ------------------------------------------------------------------------------------------------
print("# Installer options and the guides")

stack = read(STACK)
help_out = subprocess.run(["bash", str(STACK), "--help"], capture_output=True, text=True)
expect_equal("lamp-lapp-stack.sh --help exits 0", 0, help_out.returncode)
help_opts = set()
for line in help_out.stdout.splitlines():
    if re.match(r"^  -", line):
        head = re.split(r"\s{2,}", line.strip())[0]
        help_opts |= set(re.findall(r"(?<![\w-])(--?[a-z][a-z-]*)", head))
help_opts -= {"-h", "--help"}

parse_fn = re.search(r"lls_parse_args\(\) \{(.*?)\n    \}", stack, re.S).group(1)
parsed_opts = set()
for pattern in re.findall(r"^\s+([-|a-z ]+)\)", parse_fn, re.M):
    parsed_opts |= {p.strip() for p in pattern.split("|") if p.strip().startswith("-")}
parsed_opts -= {"-h", "--help"}
expect_equal("--help lists exactly the options the parser accepts", sorted(parsed_opts), sorted(help_opts))

for lang, path in GUIDES.items():
    text = read(path)
    table = next((t for t in tables(text) if t["header"][0] in ("Option", "Opzione")), None)
    if table is None:
        fail(f"{lang}: the guide has the options table")
        continue
    doc_opts = set()
    for row in table["rows"]:
        doc_opts |= set(re.findall(r"(?<![\w-])(--?[a-z][a-z-]*)", row[0]))
    expect_equal(f"{lang}: the options table lists the installer's options", sorted(help_opts), sorted(doc_opts))


def ps_params(path):
    m = re.search(r"^param \((.*?)^\)", read(path), re.S | re.M)
    return set(re.findall(r"\$(\w+)", m.group(1))) if m else set()


win_params = ps_params(WIN11)
boot_params = ps_params(BOOT)
readme = read(README)
readme_table = next((t for t in tables(readme) if t["header"][0] == "Option"), None)
readme_params = set()
for row in readme_table["rows"] if readme_table else []:
    readme_params |= set(re.findall(r"`-(\w+)", row[0]))
expect_equal("the README options table lists the bootstrap's parameters", sorted(boot_params), sorted(readme_params))
expect_equal("win11.ps1 takes the bootstrap's parameters, plus -StackScript", sorted(boot_params | {"StackScript"}), sorted(win_params))
if "`-StackScript <path>`" in readme:
    ok("the README explains -StackScript")
else:
    fail("the README explains -StackScript")

# ------------------------------------------------------------------------------------------------
print("# One version and one set of facts")

version = shell_var(stack, "LLS_VERSION")
win11 = read(WIN11)
win_version = re.search(r'^\$scriptVersion = "([^"]+)"', win11, re.M).group(1)
expect_equal("win11.ps1 and lamp-lapp-stack.sh carry the same version", version, win_version)
for path in (STACK, WIN11):
    expect_equal(f"the header of {path.name} names version {version}", version,
                 re.search(r"^# Version: (\S+)", read(path), re.M).group(1))
m = re.search(r"Ubuntu 26\.04 on Windows  -  v(\S+)", readme)
expect_equal("the README's sample banner shows the same version", version, m.group(1) if m else None)

php_all = shell_var(stack, "LLS_PHP_ALL").split()
php_mods = shell_var(stack, "LLS_PHP_MODS").split()
mariadb = shell_var(stack, "LLS_MARIADB_SERIES")
pg = re.search(r'^\s*OPT_PG="(\d+)"', stack, re.M).group(1)
nvm = shell_var(stack, "LLS_NVM_VERSION")
verify = read(VERIFY)
expect_equal("verify-stack.sh expects the installer's PHP versions", php_all,
             re.search(r'^PHP_ALL="([^"]+)"', verify, re.M).group(1).split())
expect_equal("verify-stack.sh expects the installer's PostgreSQL default", pg,
             re.search(r'^PG="\$\{PG:-(\d+)\}"', verify, re.M).group(1))
expect_equal("verify-stack.sh expects the installer's nvm version", nvm.lstrip("v").replace(".", r"\."),
             re.search(r"'\^(\S+?) \(v", verify).group(1))
expect_equal("verify-stack.sh expects the installer's MariaDB series", mariadb.replace(".", r"\."),
             re.search(r"MariaDB is \S+\" '\^(\S+?)\\\.'", verify).group(1) if re.search(r"MariaDB is \S+\" '\^(\S+?)\\\.'", verify) else None)

for lang, path in GUIDES.items():
    text = read(path)
    rows = {r[0]: r for t in tables(text) for r in t["rows"]}
    php_row = rows.get("PHP (CLI + FPM)")
    expect_equal(f"{lang}: the components table lists the installer's PHP versions", php_all,
                 [v.strip() for v in php_row[1].split(",")] if php_row else None)
    expect_equal(f"{lang}: the components table names MariaDB {mariadb}", f"{mariadb} LTS",
                 rows.get("MariaDB", [None, None])[1])
    expect_equal(f"{lang}: the components table names PostgreSQL {pg}", pg, rows.get("PostgreSQL", [None, None])[1])
    m = re.search(r"`phpX\.Y-` \+ `([^`]+)`", text)
    expect_equal(f"{lang}: the extensions list of 4.3 is the installer's", php_mods, m.group(1).split() if m else None)
    blocks = {name: body for _, body, name in code_blocks(text) if name}
    php_block = blocks.get("php-packages", "")
    for v, mods in (("8.5", [x for x in php_mods if x != "opcache"]), ("8.4", php_mods)):
        m = re.search(rf"php{re.escape(v)}-\{{([^}}]+)\}}", php_block)
        expect_equal(f"{lang}: the manual PHP {v} command installs the installer's extensions", mods,
                     m.group(1).split(",") if m else None)
    newest = max(php_all, key=lambda v: tuple(map(int, v.split("."))))
    expect_equal(f"{lang}: the manual steps set PHP {newest} as default", True,
                 f"/usr/bin/php{newest}" in blocks.get("stack-packages", ""))
    expect_equal(f"{lang}: the manual steps install PostgreSQL {pg}", True,
                 f"postgresql-{pg} " in blocks.get("stack-packages", ""))
    expect_equal(f"{lang}: the manual MariaDB repository is the {mariadb} series", True,
                 f"mariadb-{mariadb} " in blocks.get("mariadb-repository", ""))

php_range = f"{php_all[0]}-{php_all[-1]}"
expect_equal(f"win11.ps1 announces PHP {php_range} in both languages", 2, win11.count(f"PHP {php_range},"))
expect_equal(f"the README announces PHP {php_all[0]} to {php_all[-1]}", True,
             f"PHP {php_all[0]} to **{php_all[-1]}**" in readme and f"from {php_all[0]} to {php_all[-1]}" in readme)
expect_equal(f"the README names MariaDB {mariadb} and PostgreSQL {pg}", True,
             f"MariaDB {mariadb} LTS" in readme and f"PostgreSQL {pg}" in readme)

dates = {}
m = re.search(r"Last updated at: _(\d{4})-(\d\d)-(\d\d)_", read(GUIDES["en"]))
dates["en"] = m.groups() if m else None
m = re.search(r"Ultimo aggiornamento: _(\d\d)/(\d\d)/(\d{4})_", read(GUIDES["it"]))
dates["it"] = (m.group(3), m.group(2), m.group(1)) if m else None
expect_equal("both guides carry the same \"last updated\" date", dates["en"], dates["it"])

# ------------------------------------------------------------------------------------------------
print("# English and Italian guides")

en, it = read(GUIDES["en"]), read(GUIDES["it"])
expect_equal("same section structure (levels and numbers)",
             [(lvl, re.match(r"[\d.]*", t).group(0)) for lvl, t in headings(en)],
             [(lvl, re.match(r"[\d.]*", t).group(0)) for lvl, t in headings(it)])
en_blocks, it_blocks = code_blocks(en), code_blocks(it)
expect_equal("same number of code blocks", len(en_blocks), len(it_blocks))
for i, (a, b) in enumerate(zip(en_blocks, it_blocks), 1):
    if a[0] != b[0] or a[2] != b[2] or strip_comments(a[0], a[1]) != strip_comments(b[0], b[1]):
        fail(f"code block {i} ({a[0]}) is the same in both guides, comments aside", f"en:\n{a[1]}\nit:\n{b[1]}")
ok("code blocks compared")
expect_equal("same tables (count and rows)", [len(t["rows"]) for t in tables(en)], [len(t["rows"]) for t in tables(it)])
ext = lambda text: sorted(u for u in links(text) if u.startswith("http"))
expect_equal("same external links", ext(en), ext(it))
local = lambda text: sorted(u.split("#")[0] for u in links(text) if not u.startswith("http") and not u.startswith("#"))
expect_equal("same links into the repository", local(en), local(it))
expect_equal("same number of in-page links", len([u for u in links(en) if u.startswith("#")]),
             len([u for u in links(it) if u.startswith("#")]))

# ------------------------------------------------------------------------------------------------
print("# Links and anchors")

for doc in DOCS:
    for url in links(read(doc)):
        target, _, anchor = url.partition("#")
        where = f"{doc.relative_to(ROOT)}: {url}"
        if target.startswith(THIS_REPO + "/blob/main/"):
            target = "/" + target[len(THIS_REPO + "/blob/main/"):]
        elif target.startswith(THIS_REPO + "/actions/workflows/"):
            path = ROOT / ".github/workflows" / target[len(THIS_REPO + "/actions/workflows/"):].split("/")[0]
            (ok if path.exists() else fail)(f"{where} (workflow exists)")
            continue
        if target.startswith(GASH_REPO_URL + "/blob/main/"):
            if GASH is None:
                continue
            path = GASH / target[len(GASH_REPO_URL + "/blob/main/"):]
            if not path.exists():
                fail(f"{where} (not in Gash main)")
            elif anchor and path.suffix == ".md" and anchor not in anchors(path):
                fail(f"{where} (no such anchor in Gash)")
            else:
                ok(where)
            continue
        if target.startswith("http") or target.startswith("mailto:"):
            continue
        if target == "":
            path = doc
        elif target.startswith("/"):
            path = ROOT / target.lstrip("/")
        else:
            path = (doc.parent / target).resolve()
        if not path.exists():
            fail(f"{where} (missing file)")
        elif anchor and path.suffix == ".md" and anchor not in anchors(path):
            fail(f"{where} (missing anchor)", sorted(anchors(path)))
        else:
            ok(where)

# ------------------------------------------------------------------------------------------------
if GASH is not None:
    print("# Gash commands shown in the documents")
    reference, names = {}, set()
    for ref in sorted(GASH.glob("docs/**/reference.md")):
        text = ref.read_text(encoding="utf-8")
        for m in re.finditer(r"^### (gash(?: [a-z0-9-]+)*)\s*\n+```text\n(.*?)^```", text, re.S | re.M):
            reference[m.group(1)] = m.group(2)
        names |= set(re.findall(r"`([A-Za-z0-9_.-]+)`", text))
    if not reference:
        fail("Gash's reference documents parse")

    def check_command(cmd, where):
        words = cmd.split()
        if words and words[0] != "gash":
            return
        tokens = []
        for w in words:
            if w in ("|", "&&", ";", "#") or w.startswith("#"):
                break
            tokens.append(w)
        best = 0
        for i in range(1, len(tokens) + 1):
            if " ".join(tokens[:i]) in reference:
                best = i
        name = " ".join(tokens[:best])
        if best < 2:
            fail(f"{where}: `{cmd}` is a Gash command")
            return
        block = reference[name]
        rest = tokens[best:]
        if rest and re.match(r"^[a-z][a-z-]*$", rest[0]) and "Available Commands:" in block:
            fail(f"{where}: `{cmd}`: `{rest[0]}` is not a subcommand of `{name}`")
            return
        for t in rest:
            if t == "--":
                break
            if t.startswith("--"):
                flag = t.split("=", 1)[0]
                if not re.search(rf"(?<![\w-]){re.escape(flag)}(?![\w-])", block):
                    fail(f"{where}: `{name}` has no flag {flag}")
                    return
        ok(f"{where}: {' '.join(tokens)}")

    for doc in DOCS:
        text = read(doc)
        rel = doc.relative_to(ROOT)
        for span in inline_code(text):
            if span.startswith("gash "):
                check_command(span, rel)
            for m in re.finditer(r"\$\((gash [^)]*)\)", span):
                check_command(m.group(1), rel)
        for lang, body, _ in code_blocks(text):
            if lang in ("bash", "sh", ""):
                for line in body.splitlines():
                    line = line.strip()
                    if line.startswith("gash "):
                        check_command(line, rel)
                    for m in re.finditer(r"\$\((gash [^)]*)\)", line):
                        check_command(m.group(1), rel)
    for n in GASH_NAMES:
        (ok if n in names else fail)(f"Gash defines `{n}`")

# ------------------------------------------------------------------------------------------------
print("# Files")

raw = BOOT.read_bytes()
expect_equal("install.ps1 is ASCII without a BOM (it runs through Invoke-Expression)", True,
             not raw.startswith(b"\xef\xbb\xbf") and all(b < 128 for b in raw))
raw = WIN11.read_bytes()
expect_equal("win11.ps1 has non-ASCII text and the UTF-8 BOM that PowerShell 5.1 needs for it", True,
             raw.startswith(b"\xef\xbb\xbf"))
messages = {}
for lang in ("en", "it"):
    m = re.search(rf'^    "{lang}" = @\{{\n(.*?)^    \}}', read(WIN11), re.S | re.M)
    messages[lang] = sorted(re.findall(r'^        "(\w+)" = ', m.group(1), re.M)) if m else None
expect_equal("win11.ps1 has every message in English and in Italian", messages["en"], messages["it"])
for path in sorted((ROOT / "tests").rglob("*.ps1")):
    raw = path.read_bytes()
    expect_equal(f"{path.relative_to(ROOT)} is ASCII (PSScriptAnalyzer wants a BOM otherwise)", True, all(b < 128 for b in raw))
try:
    data = json.loads(read(VSCODE))
    ok("confs/vscode.json is valid JSON")
    expect_equal("confs/vscode.json has no placeholders", False, "##" in read(VSCODE))
except ValueError as e:
    fail("confs/vscode.json is valid JSON", e)

print()
if failures:
    print(f"# {len(failures)} check(s) failed")
    sys.exit(1)
print("# all checks passed")
