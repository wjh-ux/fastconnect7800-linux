#!/usr/bin/env bash
# local replica of the CI "markdown link sanity" step, so it can be tested
# before pushing (bash tests/links.sh)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

fail=0
for md in README.md README.en.md COMPATIBILITY.md CONTRIBUTING.md SECURITY.md \
          docs/EXPECTED.md docs/EVIDENCE.md docs/OPENWRT.md \
          docs/FIRST-BOOT-OPENWRT.md; do
	[ -f "$md" ] || { echo "missing: $md"; fail=1; continue; }
	base=$(dirname "$md")
	while IFS= read -r l; do
		case "$l" in
			''|http*|mailto*|'#'*|./*|../*|/*) continue ;;
		esac
		if [ ! -e "$base/$l" ] && [ ! -e "$l" ]; then
			echo "$md: broken link: $l"
			fail=1
		fi
	done < <(grep -oE '\]\([^)]+\)' "$md" \
	         | sed -e 's/^](//' -e 's/)$//' \
	         | sed -e 's/[[:space:]].*$//' -e 's/#.*$//' \
	         | sort -u)
done

if [ "$fail" -eq 0 ]; then
	echo "all relative links resolve"
fi
exit $fail
