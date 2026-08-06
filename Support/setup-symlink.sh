#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd -- "${script_dir}/.." && pwd)"
config_root="${XDG_CONFIG_HOME:-${HOME}/.config}"
plugins_dir="${config_root}/DankMaterialShell/plugins"
destination="${plugins_dir}/dmsVikunja"

mkdir -p -- "${plugins_dir}"

if [[ -e "${destination}" && ! -L "${destination}" ]]; then
    printf 'Refusing to replace non-symlink path: %s\n' "${destination}" >&2
    exit 1
fi

if [[ -L "${destination}" && "$(readlink -f -- "${destination}")" == "${plugin_dir}" ]]; then
    printf 'dms-vikunja is already linked at %s\n' "${destination}"
    exit 0
fi

ln -sfn -- "${plugin_dir}" "${destination}"
printf 'Linked dms-vikunja to %s\n' "${destination}"
