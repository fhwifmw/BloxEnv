#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${BLOXENV_REPO_URL:-https://github.com/fhwifmw/BloxEnv.git}"
REF="${BLOXENV_REF:-main}"
INSTALL_DIR="${BLOXENV_INSTALL_DIR:-$HOME/.local/bin}"

fail() {
    printf 'BloxEnv installer: %s\n' "$1" >&2
    exit 1
}

command -v git >/dev/null 2>&1 || fail "git is required"
command -v cmake >/dev/null 2>&1 || fail "cmake is required (macOS: brew install cmake)"
command -v c++ >/dev/null 2>&1 || fail "a C++ compiler is required (macOS: xcode-select --install)"

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t bloxenv)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Downloading BloxEnv..."
git clone --quiet --depth 1 --branch "$REF" "$REPO_URL" "$tmp_dir/BloxEnv"

echo "Building BloxEnv..."
cmake -S "$tmp_dir/BloxEnv" -B "$tmp_dir/BloxEnv/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$tmp_dir/BloxEnv/build" --target bloxenv --parallel

binary="$tmp_dir/BloxEnv/build/bloxenv"
[[ -x "$binary" ]] || fail "build completed but the bloxenv executable was not found"

mkdir -p "$INSTALL_DIR"
cp "$binary" "$INSTALL_DIR/bloxenv"
chmod +x "$INSTALL_DIR/bloxenv"

if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]]; then
    path_line='export PATH="$HOME/.local/bin:$PATH"'
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh) profile="$HOME/.zshrc" ;;
        bash) profile="$HOME/.bashrc" ;;
        *) profile="$HOME/.profile" ;;
    esac

    touch "$profile"
    grep -Fqx "$path_line" "$profile" || printf '\n%s\n' "$path_line" >> "$profile"
    export PATH="$HOME/.local/bin:$PATH"
fi

hash -r 2>/dev/null || true
"$INSTALL_DIR/bloxenv" --version
printf '\nInstalled to %s\n' "$INSTALL_DIR/bloxenv"
printf 'Open a new terminal, then run: bloxenv path/to/script.luau\n'
