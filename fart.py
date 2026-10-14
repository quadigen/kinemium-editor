import argparse
from pathlib import Path
import unicodedata

# File extensions to process. Use None to process all files.
EXTENSIONS = {
    ".py", ".lua", ".luau", ".odin", ".c", ".h", ".cpp", ".hpp",
    ".cs", ".js", ".ts", ".json", ".xml", ".html", ".css",
    ".md", ".txt", ".toml", ".yaml", ".yml", ".ini", ".cfg",
    ".glsl", ".vert", ".frag", ".mat"
}

def remove_special_unicode(text: str) -> str:
    result = []

    for char in text:
        category = unicodedata.category(char)

        # Preserve normal whitespace, including tabs and newlines.
        if char in "\n\r\t":
            result.append(char)
        elif category.startswith("C"):
            # Remove control, format, surrogate, private-use,
            # and unassigned characters.
            continue
        elif category in {"Zl", "Zp"}:
            # Normalize unusual Unicode line separators.
            result.append("\n")
        elif category == "Cf":
            continue
        elif ord(char) > 127:
            # Remove non-ASCII characters, including emoji
            # and accented letters.
            continue
        else:
            result.append(char)

    return "".join(result)


def process_file(path: Path, dry_run: bool) -> bool:
    try:
        original = path.read_bytes()

        # Preserve UTF-8 BOM if present.
        bom = original.startswith(b"\xef\xbb\xbf")
        encoding = "utf-8-sig" if bom else "utf-8"

        text = original.decode(encoding)
        cleaned = remove_special_unicode(text)
        output = cleaned.encode("utf-8-sig" if bom else "utf-8")

        if output == original:
            return False

        if dry_run:
            print(f"[WOULD CHANGE] {path}")
        else:
            path.write_bytes(output)
            print(f"[CLEANED] {path}")

        return True

    except (OSError, UnicodeError) as error:
        print(f"[ERROR] {path}: {error}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Remove special Unicode characters from files."
    )
    parser.add_argument("directory", type=Path, help="Directory to scan")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually modify files instead of performing a dry run",
    )
    parser.add_argument(
        "--all-files",
        action="store_true",
        help="Process every file, regardless of extension",
    )
    args = parser.parse_args()

    root = args.directory.resolve()

    if not root.is_dir():
        parser.error(f"Not a directory: {root}")

    changed = 0

    for path in root.rglob("*"):
        if not path.is_file():
            continue

        if not args.all_files and path.suffix.lower() not in EXTENSIONS:
            continue

        if process_file(path, dry_run=not args.apply):
            changed += 1

    print(f"\nFinished. {'Changed' if args.apply else 'Would change'}: {changed} file(s).")


if __name__ == "__main__":
    main()
