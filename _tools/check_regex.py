"""Compile every raw-string regex literal in a Python file.

Written because two multi-minute runs of run_tasks.py died on a single
malformed pattern, and both times the error was only visible at run time.
`python -c` with nested quoting cannot be trusted to check a file for this,
so the checker is a file too.

    python _tools/check_regex.py _tools/run_tasks.py
"""
import ast
import re
import sys


def literals(path):
    """Yield only string literals that are actually used as regex patterns.

    Matching on "contains a metacharacter" gives false positives -- "  (" and
    "?)" in ordinary prose are not patterns -- so the call is checked instead:
    a literal is a pattern only if it is an argument to re.search/compile/
    finditer/match/sub, directly or in a tuple that feeds one of those.
    """
    tree = ast.parse(open(path, encoding="utf-8").read(), path)
    patterns = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        name = getattr(fn, "attr", getattr(fn, "id", ""))
        if name not in {"search", "match", "fullmatch", "finditer", "findall",
                        "sub", "subn", "compile", "split"}:
            continue
        if not isinstance(fn, ast.Attribute) and not isinstance(
                fn, ast.Name):
            continue
        mod_ok = (isinstance(fn, ast.Attribute)
                  and isinstance(fn.value, ast.Name)
                  and fn.value.id == "re") or (
                  isinstance(fn, ast.Name) and fn.id == "re")
        if not mod_ok:
            continue
        for a in node.args:
            if isinstance(a, ast.Constant) and isinstance(a.value, str):
                patterns.setdefault(a.value, a.lineno)
            # walk into the list/tuple of a loop over patterns
            if isinstance(a, (ast.List, ast.Tuple)):
                for el in a.elts:
                    if isinstance(el, ast.Constant) and isinstance(el.value, str):
                        patterns.setdefault(el.value, el.lineno)
    return patterns.items()


def main():
    bad = 0
    checked = 0
    for path in sys.argv[1:]:
        for val, lineno in literals(path):
            checked += 1
            try:
                re.compile(val)
            except re.error as e:
                print(f"BAD  {path}:{lineno}  {val[:70]!r}\n     -> {e}")
                bad += 1
    print(f"{checked} pattern literals checked in {len(sys.argv)-1} file(s), "
          f"{bad} bad")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
