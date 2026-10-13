#!/usr/bin/env bash
# Builds the ballerina-runtime component for one platform: the upstream distribution flattened, with
# its launcher patched (ballerina-runtime/*.patch). Installers bundle this zip and the update source publishes the same one,
# so a seeded runtime and an updated one are identical.
#
# Usage: package-ballerina-runtime.sh <ballerina_version> <platform> <out_dir> [upstream_zip]
#   platform: linux | macos | macos-arm | windows (upstream asset suffix)
#   upstream_zip: use this file instead of downloading from ballerina-distribution
# Output: <out_dir>/ballerina-runtime-<ballerina_version>-<platform>.zip
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <ballerina_version> <platform> <out_dir> [upstream_zip]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BALLERINA_VERSION="$1"
PLATFORM="$2"
OUT_DIR="$3"
UPSTREAM_ZIP="${4:-}"

case "${PLATFORM}" in
  linux|macos|macos-arm|windows) ;;
  *) echo "Error: unsupported platform '${PLATFORM}'" >&2; exit 1 ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

if [ -z "${UPSTREAM_ZIP}" ]; then
  # Pre-release tags carry a suffix the asset names drop (v2201.13.6-alpha2 -> ballerina-2201.13.6-*).
  URL="https://github.com/ballerina-platform/ballerina-distribution/releases/download/v${BALLERINA_VERSION}/ballerina-${BALLERINA_VERSION%%-*}-swan-lake-${PLATFORM}.zip"
  UPSTREAM_ZIP="${WORK}/upstream.zip"
  echo "Downloading ${URL}"
  curl -fsSL --retry 3 -o "${UPSTREAM_ZIP}" "${URL}"
fi

unzip -q "${UPSTREAM_ZIP}" -d "${WORK}/upstream"
DIST_DIRS=("${WORK}"/upstream/*/distributions/*/)
if [ "${#DIST_DIRS[@]}" -ne 1 ] || [ ! -d "${DIST_DIRS[0]}" ]; then
  echo "Error: expected exactly one distributions/<dist> directory in ${UPSTREAM_ZIP}" >&2
  exit 1
fi

STAGE="${WORK}/stage"
mv "${DIST_DIRS[0]}" "${STAGE}"
rm -rf "${STAGE}/docs" "${STAGE}/examples"

# Our launcher changes ride on upstream's script as patches. No fuzz: if upstream reworks the lines
# they touch, fail here and refresh the patch (diff -u against the new upstream script).
apply_patch() {
  patch -s -N -F0 -p1 -d "${STAGE}" < "${SCRIPT_DIR}/ballerina-runtime/$1"
}
if [ "${PLATFORM}" = "windows" ]; then
  # The patch is LF; restore CRLF after, since cmd.exe mis-parses labels and gotos in LF batch files.
  tr -d '\r' < "${STAGE}/bin/bal.bat" > "${WORK}/bal.bat"
  mv "${WORK}/bal.bat" "${STAGE}/bin/bal.bat"
  apply_patch bal.bat.patch
  awk '{ printf "%s\r\n", $0 }' "${STAGE}/bin/bal.bat" > "${WORK}/bal.bat"
  mv "${WORK}/bal.bat" "${STAGE}/bin/bal.bat"
else
  apply_patch bal.patch
fi
chmod +x "${STAGE}"/bin/*

mkdir -p "${OUT_DIR}"
OUT_ZIP="$(cd "${OUT_DIR}" && pwd)/ballerina-runtime-${BALLERINA_VERSION}-${PLATFORM}.zip"
rm -f "${OUT_ZIP}"
(cd "${STAGE}" && zip -qrX "${OUT_ZIP}" .)
echo "Wrote ${OUT_ZIP}"
