#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/floot_export.py --check
VERSION_NAME="$(tr -d '\r\n' < VERSION)"
BUILD_NO="${GITHUB_RUN_NUMBER:-1}.${GITHUB_RUN_ATTEMPT:-1}"
mkdir -p build
xcodebuild -version | tee build/xcode-version.txt
npm install --global pnpm@10.13.1
pnpm install --frozen-lockfile --ignore-scripts
if ! gem list --installed --exact cocoapods --version 1.16.2 >/dev/null; then gem install cocoapods --version 1.16.2 --no-document; fi
(cd ios/App && pod _1.16.2_ install)
rm -rf build/Muwa.xcarchive build/Muwa.xcresult build/package
xcodebuild -workspace ios/App/App.xcworkspace -scheme App -configuration Release -sdk iphoneos   -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData -archivePath build/Muwa.xcarchive   -resultBundlePath build/Muwa.xcresult CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''   DEVELOPMENT_TEAM='' MARKETING_VERSION="$VERSION_NAME" CURRENT_PROJECT_VERSION="$BUILD_NO" archive 2>&1 | tee build/xcodebuild.log
mkdir -p build/package/Payload
ditto build/Muwa.xcarchive/Products/Applications/App.app build/package/Payload/Muwa.app
find build/package/Payload -type d -name _CodeSignature -prune -exec rm -rf '{}' +
find build/package/Payload -name embedded.mobileprovision -type f -delete
(cd build/package && /usr/bin/zip -qry -y ../Muwa.ipa Payload)
python3 scripts/verify_ipa.py build/Muwa.ipa
cp ios/App/Podfile.lock build/Podfile.lock
shasum -a 256 build/Muwa.ipa > build/Muwa.ipa.sha256
