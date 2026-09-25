#!/bin/bash

SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
APP_PATH="$(dirname "${SELF_PATH}")"
ROOT_PATH="$(dirname "${APP_PATH}")"

cd "${ROOT_PATH}" || exit 1


MAX_NAME_BYTES=256 # ext4 держит имя до 255 байт включительно, режем только то, что длиннее
IGNORE_PATTERNS="$(printf '?%.0s' $(seq 1 ${MAX_NAME_BYTES}))*"
COPIES_PATH='copies'
STAMP_FILE='date_last_backup.txt'
SHELF_LIFE=180 # срок хранения
REMOTE_SSH='koren-backup@koren2.ru'
REMOTE_KEY='/home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru'

source "${APP_PATH}/get_changes.sh"
source "${APP_PATH}/get_ignored.sh"

function rsync_run ()
{
	local remote_ssh="$1" # удаленный ssh
	local remote_key="$2" # ключ ssh
	local external_path="$3" # внешний путь
	local internal_path="$4" # внутренний путь

	local latest_path="${internal_path}/latest"
	local latest_image_path="${latest_path}/image"
	local date time
	read -r date time <<< "$(date '+%F %T')"
	local date_path="${internal_path}/${date}_${time//:/-}"
	local date_image_path="${date_path}/image"

	mkdir -p "${latest_image_path}"

	echo ''
	echo '----- ----- ----- ----- -----'
	echo ''
	echo "remote_ssh: ${remote_ssh}"
	echo "external_path: ${external_path}"
	echo "internal_path: ${internal_path}"

	# ===== ===== ===== sync ===== ===== =====

	echo ''
	echo '[rsync]'

	local stats
	# --human-readable дважды — не опечатка: один раз — единицы по 1000 (kB), два — по 1024 (KiB)
	stats=$(rsync --stats --human-readable --human-readable --archive --delete --numeric-ids --delete-excluded \
		--rsh="/usr/bin/ssh -i ${remote_key}" \
		--exclude="${IGNORE_PATTERNS}" \
		"${remote_ssh}:${external_path}" \
		"${latest_image_path}")

	local rsync_status=$?

	echo "${stats}"

	if [[ ${rsync_status} -eq 0 ]]; then
		echo "${date}" > "${latest_path}/${STAMP_FILE}"
		echo "date_last_backup: ${date}"
	else
		echo "ERROR: rsync failed with exit code ${rsync_status}!" >&2
	fi

	if ! grep -qE '^Number of (created|deleted|regular files transferred): [1-9]' <<< "${stats}"; then
		echo 'no changes'
		return
	fi

	mkdir -p "${date_image_path}"
	cp -al "${latest_image_path}/." "${date_image_path}"

	# ===== ===== ===== ignored ===== ===== =====

	echo ''
	echo '[ignored]'

	local ignored
	ignored=$(get_ignored "${remote_ssh}" "${remote_key}" "${external_path}")

	echo "${ignored}" > "${date_path}/ignored.txt"
	echo "${ignored}"

	# ===== ===== ===== rsnapshot-diff ===== ===== =====

	echo ''
	echo '[rsnapshot-diff]'

	local previous_path
	previous_path=$(find "${internal_path}" -mindepth 1 -maxdepth 1 -type d -name '????-??-??_??-??-??' ! -path "${date_path}" | sort | tail -n 1)

	if [[ -n "${previous_path}" ]];
	then
		echo "previous_path: ${previous_path}"
		echo "date_path: ${date_path}"

		local previous_image_path="${previous_path}/image"

		local rsnapshot_diff
		rsnapshot_diff=$(rsnapshot-diff -v "${previous_image_path}" "${date_image_path}")

		echo "${rsnapshot_diff}" > "${date_path}/rsnapshot.diff"
		get_changes "${rsnapshot_diff}" > "${date_path}/changed.diff"
	else
		echo '-- empty --'
	fi

	# ===== ===== ===== config ===== ===== =====

	echo ''
	echo '[config]'

	{
		echo '[backup]'
		echo "date = ${date}"
		echo "time = ${time}"
		echo "remote_ssh = ${remote_ssh}"
		echo "remote_key = ${remote_key}"
		echo "external_path = ${external_path}"
		echo "previous_path = ${previous_path}"
		echo "max_name_bytes = ${MAX_NAME_BYTES}"
	} | tee "${date_path}/config.ini"

	# ===== ===== ===== deleting old backups ===== ===== =====

	echo ''
	echo '[deleting old backups]'
	find "${internal_path}" -mindepth 1 -maxdepth 1 ! -name "latest" -mtime "+${SHELF_LIFE}" -prune -print0 | xargs -0 rm -rfv
}

echo ''
echo '===== ===== ===== ===== ===== ====='
echo ''
echo "STARTED: $(date '+%Y-%m-%d %H:%M:%S')"

rsync_run "${REMOTE_SSH}" "${REMOTE_KEY}" '/media/koren/server/storage/' "${COPIES_PATH}/storage"
# rsync_run "${REMOTE_SSH}" "${REMOTE_KEY}" '~/backup_check' "${COPIES_PATH}/backup_check"

echo ''
echo '----- ----- ----- ----- -----'
echo ''
echo "SECONDS: ${SECONDS}"
