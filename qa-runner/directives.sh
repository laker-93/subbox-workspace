#!/usr/bin/env bash
# Print the directive queue (IN PROGRESS + PENDING from directives.md) for the
# `directives` / `directive` Discord command. Split out of status.sh, which now
# reports the live run instead.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

section() {  # print the body of a "## <name>" section of directives.md, sans HTML comments
  awk -v want="## $1" '
    $0==want {grab=1; next}
    /^## / {grab=0}
    grab {print}
  ' "$DIRECTIVES" | sed '/<!--/,/-->/d' | sed '/^[[:space:]]*$/d'
}

echo "**subbox QA — directives**"
echo
echo "__In progress__"
ip="$(section 'IN PROGRESS')"; echo "${ip:-_(nothing)_}"
echo
echo "__Pending (queued from you / coverage)__"
pd="$(section 'PENDING')"; echo "${pd:-_(none)_}"
