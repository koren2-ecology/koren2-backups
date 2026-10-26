#!/bin/bash

SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
APP_PATH="$(dirname "${SELF_PATH}")"
ROOT_PATH="$(dirname "${APP_PATH}")"

cd "${ROOT_PATH}" || exit 1


MAX_NAME_BYTES=256 # ext4 держит имя до 255 байт включительно, режем только то, что длиннее
IGNORE_PATTERNS="$(printf '?%.0s' $(seq 1 ${MAX_NAME_BYTES}))*"
COPIES_PATH='copies'
STAMP_FILE='date_last_backup.txt'
IGNORED_FILE='ignored.txt'
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
	local latest_ignored_path="${latest_path}/${IGNORED_FILE}"
	local date time
	read -r date time <<< "$(date '+%F %T')"
	local date_path="${internal_path}/${date}_${time//:/-}"
	local date_image_path="${date_path}/image"

	mkdir -p "${latest_image_path}"

	echo ''
	echo '----- ----- ----- ----- -----'
	echo ''
	echo "${remote_ssh}:${external_path} → ${internal_path}"

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
	echo ''

	# итоговые строки выровнены табами под ширину 8: короткие ключи — два таба, date_last_backup — один
	if [[ ${rsync_status} -eq 0 ]]; then
		echo "${date}" > "${latest_path}/${STAMP_FILE}"
		printf 'date_last_backup:\t%s\n' "${date}"
	else
		echo "ERROR: rsync failed with exit code ${rsync_status}!" >&2
	fi

	if ! grep -qE '^Number of (created|deleted|regular files transferred): [1-9]' <<< "${stats}"; then
		printf 'snapshot:\t\t%s\n' 'no changes'
		return
	fi

	mkdir -p "${date_image_path}"
	cp -al "${latest_image_path}/." "${date_image_path}"

	printf 'snapshot:\t\t%s\n' "${date_path##*/}"

	# ===== ===== ===== ignored ===== ===== =====

	local ignored
	ignored=$(get_ignored "${remote_ssh}" "${remote_key}" "${external_path}")

	# Пока список прежний, каждый новый снимок получает жёсткую ссылку на один и тот же файл.
	# Изменился — старый файл удаляем и пишем новый: у него свой inode, а снимки, которые
	# ссылались на старый, сохраняют свой список. Запись поверх переписала бы его во всех сразу.
	if [[ "${ignored}" == "$(cat "${latest_ignored_path}" 2>/dev/null)" ]];
	then
		printf 'ignored:\t\t%s\n' 'no changes'
	else
		rm -f "${latest_ignored_path}"
		echo "${ignored}" > "${latest_ignored_path}"
		printf 'ignored:\t\tchanged (%s)\n' "$(grep -c . <<< "${ignored}")"
	fi

	ln "${latest_ignored_path}" "${date_path}/${IGNORED_FILE}"

	# ===== ===== ===== rsnapshot-diff ===== ===== =====

	local previous_path
	previous_path=$(find "${internal_path}" -mindepth 1 -maxdepth 1 -type d -name '????-??-??_??-??-??' ! -path "${date_path}" | sort | tail -n 1)

	if [[ -n "${previous_path}" ]];
	then
		local previous_image_path="${previous_path}/image"

		local rsnapshot_diff
		rsnapshot_diff=$(rsnapshot-diff -v "${previous_image_path}" "${date_image_path}")

		local changes
		changes=$(get_changes "${rsnapshot_diff}")

		echo "${rsnapshot_diff}" > "${date_path}/rsnapshot.diff"
		echo "${changes}" > "${date_path}/changed.diff"
		printf 'changes:\t\t+ %s, M %s, - %s\n' "$(grep -c '^+ ' <<< "${changes}")" "$(grep -c '^M ' <<< "${changes}")" "$(grep -c '^- ' <<< "${changes}")"
	else
		printf 'changes:\t\t%s\n' 'first snapshot'
	fi

	# ===== ===== ===== config ===== ===== =====

	{
		echo '[backup]'
		echo "date = ${date}"
		echo "time = ${time}"
		echo "remote_ssh = ${remote_ssh}"
		echo "remote_key = ${remote_key}"
		echo "external_path = ${external_path}"
		echo "previous_path = ${previous_path}"
		echo "max_name_bytes = ${MAX_NAME_BYTES}"
	} > "${date_path}/config.ini"

	# ===== ===== ===== deleting old backups ===== ===== =====

	local deleted
	deleted=$(find "${internal_path}" -mindepth 1 -maxdepth 1 ! -name "latest" -mtime "+${SHELF_LIFE}" -prune -printf '%f\n' -exec rm -rf {} + | paste -sd ' ')

	printf 'deleted:\t\t%s\n' "${deleted:-none}"
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
