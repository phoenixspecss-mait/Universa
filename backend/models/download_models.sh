#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET_DIR="${1:-${ROOT_DIR}/models}"

mkdir -p "${TARGET_DIR}"

WEIGHTS_URL="https://github.com/AlexeyAB/darknet/releases/download/darknet_yolo_v4_pre/yolov4-tiny.weights"
CFG_URL="https://raw.githubusercontent.com/AlexeyAB/darknet/master/cfg/yolov4-tiny.cfg"
NAMES_URL="https://raw.githubusercontent.com/AlexeyAB/darknet/master/data/coco.names"

download_file() {
    local url="$1"
    local dest="$2"
    local filename="$(basename "${dest}")"

    if [ -s "${dest}" ]; then
        echo "[+] ${filename} already exists at ${dest}, skipping download."
    else
        echo "[*] Downloading ${filename}..."
        curl -sL "${url}" -o "${dest}"
        if [ ! -s "${dest}" ]; then
            echo "[!] Error: Failed to download ${filename} from ${url}" >&2
            rm -f "${dest}"
            exit 1
        fi
        echo "[+] Successfully downloaded ${filename} ($(du -h "${dest}" | cut -f1))."
    fi
}

echo "=== Model Download Helper ==="
echo "Target directory: ${TARGET_DIR}"

download_file "${WEIGHTS_URL}" "${TARGET_DIR}/yolov4-tiny.weights"
download_file "${CFG_URL}" "${TARGET_DIR}/yolov4-tiny.cfg"
download_file "${NAMES_URL}" "${TARGET_DIR}/coco.names"

echo "=== All models ready in ${TARGET_DIR} ==="

