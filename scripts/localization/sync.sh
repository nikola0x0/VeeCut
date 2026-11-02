#!/bin/zsh
# Builds app localization output, selects app-owned data safely, then regenerates and validates English.
set -euo pipefail

repo_root="${0:A:h:h:h}"
source_strings="$repo_root/Sources/PalmierPro/Resources/Localization/en.lproj/Localizable.strings"
temporary_directory="$(mktemp -d /private/tmp/palmier-localization.XXXXXX)"
trap 'rm -rf "$temporary_directory"' EXIT

cd "$repo_root"
# Swift Build writes each compiled file's .stringsdata next to its object files and keeps them across incremental builds.
swift build
binary_directory="$(swift build --show-bin-path)"
intermediates_directory="${binary_directory:h:h}/Intermediates.noindex"

stringsdata_arguments=()
app_stringsdata_list="$temporary_directory/app-stringsdata"
node scripts/localization/sync.mjs \
  --list-app-stringsdata "$intermediates_directory" > "$app_stringsdata_list"
while IFS= read -r data; do
  stringsdata_arguments+=(--stringsdata "$data")
done < "$app_stringsdata_list"

node scripts/localization/sync.mjs \
  --output "$source_strings" \
  "${stringsdata_arguments[@]}"
node scripts/localization/check.mjs "$@"
