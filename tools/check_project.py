#!/usr/bin/env python3
"""Static checker for SURVIVE THE NIGHT (no Luau toolchain required).

Checks:
  1. default.project.json parses and every $path exists.
  2. Builds the Rojo instance tree; reports duplicate sibling names.
  3. Tokenizes every Luau file; checks block keyword balance and bracket balance.
  4. Flags unsupported constructs for this checker (if-expressions) and deprecated globals (wait/spawn/delay).
  5. Resolves require() paths against the Rojo tree; flags client->server requires.
  6. ModuleScripts must end with a top-level `return`.
  7. Remote names used with Remotes.get("X") must be registered in Remotes.lua.
  8. GameConfig.<Key> references must exist in GameConfig.lua.
  9. Undefined global names (file-level, scope-insensitive heuristic).
 10. Secret-like strings.

This is a heuristic linter, not a compiler. Passing it does not prove the code runs.
Exit code 1 on errors.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue",
}

ROBLOX_GLOBALS = {
    "game", "workspace", "script", "plugin", "shared", "_G", "Enum", "Instance", "Vector3", "Vector2",
    "CFrame", "Color3", "UDim", "UDim2", "TweenInfo", "NumberSequence", "NumberSequenceKeypoint",
    "ColorSequence", "ColorSequenceKeypoint", "NumberRange", "Ray", "RaycastParams", "OverlapParams",
    "Random", "os", "math", "string", "table", "coroutine", "utf8", "bit32", "buffer", "debug", "print",
    "warn", "error", "assert", "pcall", "xpcall", "select", "type", "typeof", "tostring", "tonumber",
    "ipairs", "pairs", "next", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen",
    "unpack", "require", "tick", "time", "elapsedTime", "DateTime", "PhysicalProperties", "Rect", "Font",
    "PathWaypoint", "Faces", "Axes", "BrickColor", "Region3", "task", "self", "newproxy", "gcinfo",
    # type names used in annotations
    "number", "string", "boolean", "any", "never", "unknown", "thread", "Player", "Model", "BasePart",
    "Part", "Humanoid", "RemoteEvent", "Folder", "ProximityPrompt", "Sound", "Attachment", "RBXScriptConnection",
}

DEPRECATED = {"wait", "spawn", "delay"}

OPS3 = ["...", "..=", "//="]
OPS2 = ["==", "~=", "<=", ">=", "..", "::", "->", "+=", "-=", "*=", "/=", "%=", "^=", "//"]


class Tok:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind = kind
        self.value = value
        self.line = line

    def __repr__(self):
        return f"{self.kind}:{self.value}@{self.line}"


def long_bracket_level(src, i):
    """If src[i] starts a long bracket '[' '='* '[', return level, else -1."""
    if src[i] != "[":
        return -1
    j = i + 1
    level = 0
    while j < len(src) and src[j] == "=":
        level += 1
        j += 1
    if j < len(src) and src[j] == "[":
        return level
    return -1


def tokenize(src, path, errors):
    toks = []
    i = 0
    n = len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if src.startswith("--", i):
            if i + 2 < n and src[i + 2] == "[":
                level = long_bracket_level(src, i + 2)
                if level >= 0:
                    close = "]" + "=" * level + "]"
                    end = src.find(close, i + 2)
                    if end < 0:
                        errors.append(f"{path}:{line}: unterminated long comment")
                        return toks
                    line += src.count("\n", i, end)
                    i = end + len(close)
                    continue
            end = src.find("\n", i)
            i = n if end < 0 else end
            continue
        if c == "[":
            level = long_bracket_level(src, i)
            if level >= 0:
                close = "]" + "=" * level + "]"
                end = src.find(close, i)
                if end < 0:
                    errors.append(f"{path}:{line}: unterminated long string")
                    return toks
                toks.append(Tok("string", src[i:end + len(close)], line))
                line += src.count("\n", i, end)
                i = end + len(close)
                continue
        if c in "\"'`":
            quote = c
            j = i + 1
            start_line = line
            depth = 0
            while j < n:
                ch = src[j]
                if ch == "\\":
                    j += 2
                    continue
                if ch == "\n":
                    if quote != "`":
                        errors.append(f"{path}:{line}: unterminated string")
                        break
                    line += 1
                if quote == "`":
                    if ch == "{":
                        depth += 1
                    elif ch == "}":
                        depth -= 1
                if ch == quote and depth == 0:
                    break
                j += 1
            toks.append(Tok("string", src[i:j + 1], start_line))
            i = j + 1
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            m = re.match(r"0[xX][0-9a-fA-F_]+|0[bB][01_]+|(\d[\d_]*)?\.?\d[\d_]*([eE][+-]?\d+)?", src[i:])
            if not m or not m.group(0):
                m = re.match(r"\d+", src[i:])
            toks.append(Tok("number", m.group(0), line))
            i += len(m.group(0))
            continue
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
            word = m.group(0)
            kind = "keyword" if word in KEYWORDS else "name"
            toks.append(Tok(kind, word, line))
            i += len(word)
            continue
        matched = False
        for op in OPS3 + OPS2:
            if src.startswith(op, i):
                toks.append(Tok("op", op, line))
                i += len(op)
                matched = True
                break
        if matched:
            continue
        toks.append(Tok("op", c, line))
        i += 1
    return toks


EXPR_PREV = {"=", "(", ",", "{", "return", "and", "or", "..", "+", "-", "*", "/", "[", "==", "~=", "not", "<", ">", "<=", ">="}


def check_blocks(toks, path, errors):
    stack = []  # (keyword, line)
    pending_do = 0
    brackets = []
    pairs = {")": "(", "]": "[", "}": "{"}
    prev = None
    for t in toks:
        v = t.value
        if t.kind == "op":
            if v in "([{":
                brackets.append((v, t.line))
            elif v in ")]}":
                if not brackets or brackets[-1][0] != pairs[v]:
                    errors.append(f"{path}:{t.line}: unbalanced '{v}'")
                    return
                brackets.pop()
        elif t.kind == "keyword":
            if v == "if":
                if prev is not None and prev.value in EXPR_PREV and prev.kind in ("op", "keyword"):
                    errors.append(f"{path}:{t.line}: if-expression found (not supported by checker; use a statement)")
                    return
                stack.append(("if", t.line))
            elif v == "function":
                stack.append(("function", t.line))
            elif v in ("while", "for"):
                stack.append((v, t.line))
                pending_do += 1
            elif v == "do":
                if pending_do > 0:
                    pending_do -= 1
                else:
                    stack.append(("do", t.line))
            elif v == "repeat":
                stack.append(("repeat", t.line))
            elif v == "until":
                if not stack or stack[-1][0] != "repeat":
                    errors.append(f"{path}:{t.line}: 'until' without 'repeat'")
                    return
                stack.pop()
            elif v in ("elseif", "else"):
                if not stack or stack[-1][0] != "if":
                    errors.append(f"{path}:{t.line}: '{v}' outside if-block")
                    return
            elif v == "end":
                if not stack:
                    errors.append(f"{path}:{t.line}: unexpected 'end'")
                    return
                if stack[-1][0] == "repeat":
                    errors.append(f"{path}:{t.line}: 'end' closes 'repeat' (needs 'until')")
                    return
                stack.pop()
        prev = t
    if stack:
        kw, ln = stack[-1]
        errors.append(f"{path}:{ln}: unclosed '{kw}'")
    if brackets:
        b, ln = brackets[-1]
        errors.append(f"{path}:{ln}: unclosed '{b}'")
    if pending_do:
        errors.append(f"{path}: 'while'/'for' without 'do'")


# ---------------------------------------------------------------------------
# Rojo tree
# ---------------------------------------------------------------------------

class Node:
    def __init__(self, name, cls, file=None, parent=None):
        self.name = name
        self.cls = cls
        self.file = file
        self.parent = parent
        self.children = {}

    def path(self):
        parts = []
        n = self
        while n is not None and n.parent is not None:
            parts.append(n.name)
            n = n.parent
        return ".".join(reversed(parts))


def add_child(parent, node, errors):
    if node.name in parent.children:
        errors.append(f"duplicate instance name '{node.name}' under {parent.path() or 'DataModel'}")
    parent.children[node.name] = node
    node.parent = parent


def classify(filename):
    for suffix, cls in ((".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript"),
                        (".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if filename.endswith(suffix):
            return filename[: -len(suffix)], cls
    return None, None


def map_path(rel, name, errors, files):
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        errors.append(f"project $path missing: {rel}")
        return Node(name, "Folder")
    if os.path.isfile(full):
        base, cls = classify(os.path.basename(full))
        node = Node(name, cls or "Unknown", file=full)
        if cls:
            files.append((full, node))
        return node
    node = Node(name, "Folder")
    for entry in sorted(os.listdir(full)):
        sub = os.path.join(full, entry)
        if os.path.isdir(sub):
            add_child(node, map_path(os.path.relpath(sub, ROOT), entry, errors, files), errors)
        else:
            base, cls = classify(entry)
            if base is None:
                continue  # Rojo ignores unknown file types
            if base == "init":
                errors.append(f"init scripts not supported by this checker: {sub}")
                continue
            child = Node(base, cls, file=sub)
            files.append((sub, child))
            add_child(node, child, errors)
    return node


def build_tree(project, errors, files):
    root = Node("DataModel", "DataModel")

    def walk(spec, node):
        for key, value in spec.items():
            if key.startswith("$"):
                continue
            if "$path" in value:
                child = map_path(value["$path"], key, errors, files)
            else:
                child = Node(key, value.get("$className", "Service"))
            add_child(node, child, errors)
            walk(value, child)

    walk(project["tree"], root)
    return root


# ---------------------------------------------------------------------------
# Require resolution
# ---------------------------------------------------------------------------

def parse_chain(toks, i, aliases, script_node, root):
    """Parse an instance expression starting at toks[i]. Returns (node or None, next index, resolvable)."""
    t = toks[i]
    node = None
    if t.kind == "name" and t.value == "game":
        node = root
        i += 1
    elif t.kind == "name" and t.value == "script":
        node = script_node
        i += 1
    elif t.kind == "name" and t.value == "workspace":
        return None, i + 1, False
    elif t.kind == "name" and t.value in aliases:
        node = aliases[t.value]
        if node is None:
            return None, i + 1, False
        i += 1
    else:
        return None, i, False
    while i < len(toks):
        t = toks[i]
        if t.value == "." and i + 1 < len(toks) and toks[i + 1].kind == "name":
            field = toks[i + 1].value
            if field == "Parent":
                node = node.parent
            else:
                node = node.children.get(field) if node else None
            i += 2
            if node is None:
                return None, i, True
            continue
        if t.value == ":" and i + 3 < len(toks) and toks[i + 1].kind == "name" and toks[i + 2].value == "(":
            method = toks[i + 1].value
            arg = toks[i + 3]
            if method in ("GetService", "WaitForChild", "FindFirstChild") and arg.kind == "string":
                name = arg.value[1:-1]
                j = i + 4
                # skip optional extra args
                depth = 1
                while j < len(toks) and depth > 0:
                    if toks[j].value == "(":
                        depth += 1
                    elif toks[j].value == ")":
                        depth -= 1
                    j += 1
                if method == "GetService" and node is not root:
                    return None, j, False
                child = node.children.get(name) if node else None
                if method == "GetService" and child is None:
                    # services not in the project (Players, RunService, ...) are fine but unresolvable
                    return None, j, False
                node = child
                i = j
                if node is None:
                    return None, i, True
                continue
            break
        break
    return node, i, True


def under(node, top):
    while node is not None:
        if node.parent is not None and node.parent.parent is None and node.name == top:
            return True
        node = node.parent
    return False


def check_requires(toks, path, script_node, root, errors, warnings):
    aliases = {}
    i = 0
    while i < len(toks):
        t = toks[i]
        # local NAME = <chain>
        if t.value == "local" and i + 3 < len(toks) and toks[i + 1].kind == "name" and toks[i + 2].value == "=":
            name = toks[i + 1].value
            start = i + 3
            if toks[start].value == "require" and start + 1 < len(toks) and toks[start + 1].value == "(":
                i = start
                aliases[name] = None
                continue
            node, j, ok = parse_chain(toks, start, aliases, script_node, root)
            if ok and node is not None and j < len(toks) and toks[j].value not in ("(", ":", "."):
                aliases[name] = node
            else:
                aliases[name] = None
            i += 1
            continue
        if t.value == "require" and i + 1 < len(toks) and toks[i + 1].value == "(":
            node, j, ok = parse_chain(toks, i + 2, aliases, script_node, root)
            if not ok:
                warnings.append(f"{path}:{t.line}: require path not statically resolvable")
            elif node is None:
                errors.append(f"{path}:{t.line}: require target does not exist in Rojo tree")
            elif node.cls != "ModuleScript":
                errors.append(f"{path}:{t.line}: require target {node.path()} is a {node.cls}, not a ModuleScript")
            else:
                client_side = under(script_node, "StarterPlayer") or under(script_node, "ReplicatedStorage")
                server_target = under(node, "ServerScriptService") or under(node, "ServerStorage")
                if client_side and server_target:
                    errors.append(f"{path}:{t.line}: client/shared code requires server-only module {node.path()}")
            i = j
            continue
        i += 1


def check_module_return(toks, path, errors):
    depth = 0
    last_return_top = False
    opener = {"function", "if", "do", "repeat"}
    for t in toks:
        if t.kind == "keyword":
            if t.value in opener:
                depth += 1
            elif t.value in ("end", "until"):
                depth -= 1
            elif t.value == "return" and depth == 0:
                last_return_top = True
    # while/for open via 'do', which is counted above
    if not last_return_top:
        errors.append(f"{path}: ModuleScript has no top-level return")


def check_globals(toks, path, warnings):
    declared = set()
    n = len(toks)
    # collect declarations
    for i, t in enumerate(toks):
        if t.value == "local" and i + 1 < n:
            j = i + 1
            if toks[j].value == "function" and j + 1 < n:
                declared.add(toks[j + 1].value)
                continue
            while j < n and toks[j].kind == "name":
                declared.add(toks[j].value)
                j += 1
                # skip type annotation
                if j < n and toks[j].value == ":":
                    j += 2
                    while j < n and toks[j].value in ("?",):
                        j += 1
                if j < n and toks[j].value == ",":
                    j += 1
                    continue
                break
        elif t.value == "function":
            # params
            j = i + 1
            while j < n and toks[j].value != "(":
                j += 1
            j += 1
            depth = 1
            while j < n and depth > 0:
                v = toks[j].value
                if v == "(":
                    depth += 1
                elif v == ")":
                    depth -= 1
                elif toks[j].kind == "name" and depth == 1 and toks[j - 1].value in ("(", ","):
                    declared.add(toks[j].value)
                j += 1
        elif t.value == "for":
            j = i + 1
            while j < n and toks[j].value not in ("=", "in"):
                if toks[j].kind == "name":
                    declared.add(toks[j].value)
                j += 1
    # usages
    skip_type = False
    type_depth = 0
    for i, t in enumerate(toks):
        if t.kind == "name" and t.value in ("type", "export") and i + 1 < n:
            nxt = toks[i + 1]
            if t.value == "export" or (nxt.kind == "name" and i + 2 < n and toks[i + 2].value in ("=", "<")):
                if i == 0 or toks[i - 1].value not in (".", ":"):
                    skip_type = True
                    type_depth = 0
                    continue
        if skip_type:
            if t.value in ("{", "("):
                type_depth += 1
            elif t.value in ("}", ")"):
                type_depth -= 1
            elif type_depth == 0 and i + 1 < n and toks[i + 1].line != t.line and t.value not in ("|", "&", ",", "=", "->"):
                skip_type = False
            continue
        if t.kind != "name":
            continue
        prev = toks[i - 1] if i > 0 else None
        nxt = toks[i + 1] if i + 1 < n else None
        if prev is not None and prev.value in (".", ":", "->", "::"):
            continue
        if nxt is not None and nxt.value == "=" and prev is not None and prev.value in ("{", ",", ";"):
            continue  # table field
        if nxt is not None and nxt.value == ":" and prev is not None and prev.value in ("{", ","):
            continue  # typed table field
        if t.value in declared or t.value in ROBLOX_GLOBALS:
            continue
        if t.value in DEPRECATED:
            warnings.append(f"{path}:{t.line}: deprecated global '{t.value}' (use task.{t.value})")
            continue
        warnings.append(f"{path}:{t.line}: possibly undefined name '{t.value}'")


def remote_names(remotes_file):
    src = open(remotes_file, encoding="utf-8").read()
    names = set()
    for block in re.findall(r"local (?:SERVER_TO_CLIENT|CLIENT_TO_SERVER) = \{(.*?)\n\}", src, re.S):
        names.update(re.findall(r'"([A-Za-z]+)"', re.sub(r"--[^\n]*", "", block)))
    return names


def config_keys(config_file):
    src = open(config_file, encoding="utf-8").read()
    return set(re.findall(r"^GameConfig\.([A-Za-z_]+)\s*=", src, re.M))


SECRET_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"ghp_[A-Za-z0-9]{30,}"),
    re.compile(r"(?i)(api[_-]?key|secret|token)\s*=\s*\"[A-Za-z0-9/+_-]{24,}\""),
]


def main():
    errors = []
    warnings = []
    project_path = os.path.join(ROOT, "default.project.json")
    try:
        project = json.load(open(project_path, encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR default.project.json: {exc}")
        return 1

    files = []
    root = build_tree(project, errors, files)

    remotes_file = os.path.join(ROOT, "src/ReplicatedStorage/Shared/Remotes.lua")
    known_remotes = remote_names(remotes_file)
    cfg_keys = config_keys(os.path.join(ROOT, "src/ReplicatedStorage/Shared/GameConfig.lua"))

    total_lines = 0
    for full, node in files:
        rel = os.path.relpath(full, ROOT)
        src = open(full, encoding="utf-8").read()
        total_lines += src.count("\n") + 1
        toks = tokenize(src, rel, errors)
        before = len(errors)
        check_blocks(toks, rel, errors)
        if len(errors) > before:
            continue
        if node.cls == "ModuleScript":
            check_module_return(toks, rel, errors)
        check_requires(toks, rel, node, root, errors, warnings)
        check_globals(toks, rel, warnings)
        for m in re.finditer(r'Remotes\.get\("([A-Za-z]+)"\)', src):
            if m.group(1) not in known_remotes:
                line = src.count("\n", 0, m.start()) + 1
                errors.append(f"{rel}:{line}: unknown remote '{m.group(1)}'")
        for m in re.finditer(r"\bGameConfig\.([A-Za-z_]+)", src):
            if m.group(1) not in cfg_keys and not rel.endswith("GameConfig.lua"):
                line = src.count("\n", 0, m.start()) + 1
                errors.append(f"{rel}:{line}: unknown GameConfig key '{m.group(1)}'")
        for pat in SECRET_PATTERNS:
            if pat.search(src):
                errors.append(f"{rel}: secret-like string matches {pat.pattern}")

    # Every client->server remote must have an OnServerEvent handler somewhere.
    server_src = ""
    for full, node in files:
        if under(node, "ServerScriptService"):
            server_src += open(full, encoding="utf-8").read()
    c2s_block = re.search(r"local CLIENT_TO_SERVER = \{(.*?)\n\}", open(remotes_file, encoding="utf-8").read(), re.S)
    for name in re.findall(r'"([A-Za-z]+)"', re.sub(r"--[^\n]*", "", c2s_block.group(1))):
        if not re.search(r'Remotes\.get\("' + name + r'"\)\.OnServerEvent', server_src):
            errors.append(f"client->server remote '{name}' has no OnServerEvent handler")
        limit_key = name
        if limit_key not in open(os.path.join(ROOT, "src/ReplicatedStorage/Shared/GameConfig.lua"), encoding="utf-8").read():
            errors.append(f"client->server remote '{name}' has no RateLimits entry")

    print(f"Checked {len(files)} Luau files ({total_lines} lines) mapped by default.project.json")
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print(f"Summary: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
