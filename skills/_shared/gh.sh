# GitHub CLI helpers shared by the PR skills. Source it; it sources _cap.sh itself.
#
#   gh_t <args...>   gh, capped — a stalled call would otherwise kill the whole injection
#   gh_jq <filter>   jq on stdin, falling back to ghjson.py where jq is missing

_GH_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_GH_SH_DIR/_cap.sh"

gh_t() { cap 25 gh "$@" 2>/dev/null; }

# gh_t for JSON calls. cap folds stderr into stdout, so a gh error message would otherwise
# read as a successful payload; anything that isn't JSON comes back empty.
gh_json() {
  local out
  out="$(gh_t "$@")" || return 1
  case "$(printf '%s' "$out" | head -c 1)" in
    '{'|'[') printf '%s' "$out" ;;
    *) return 1 ;;
  esac
}

gh_jq() {
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" 2>/dev/null
  else
    python3 "$_GH_SH_DIR/ghjson.py" "$1" 2>/dev/null
  fi
}

# Owner/repo for the API and GraphQL calls that need them spelled out.
gh_repo_slug() { gh_t repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'; }
