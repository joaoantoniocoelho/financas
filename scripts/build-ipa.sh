#!/bin/zsh
# Builds an unsigned Financas.ipa for sideloading tools such as SideStore or AltStore,
# which sign it with your Apple ID on the iPhone and refresh it automatically.
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
archive="$project_dir/.build/ios/Financas.xcarchive"
payload="$project_dir/.build/ios/Payload"

rm -rf "$archive" "$payload"
xcodebuild archive \
  -project iOS/Financas.xcodeproj -scheme Financas \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -quiet

mkdir -p "$payload" "$project_dir/dist"
cp -R "$archive/Products/Applications/Financas.app" "$payload/"
rm -f "$project_dir/dist/Financas.ipa"
(cd "${payload:h}" && zip -qry "$project_dir/dist/Financas.ipa" Payload)
echo "$project_dir/dist/Financas.ipa"
