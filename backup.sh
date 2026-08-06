#!/bin/bash

COPIES_PATH='/mnt/backup/copies'
SHELF_LIFE=180 # срок хранения


function get_changes ()
{
	awk '

	/^[+-]/ {
		action = substr($0, 1, 1) # Получаем первый символ (+ или -)
		path = substr($0, 3)      # Получаем путь, отсекая знак и пробел

		# sub(/[[:space:]]+$/, "", path)
		sub(/check\/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\//, "", path)

		if (action == "+") plus[path] = 1
		if (action == "-") minus[path] = 1
	}

	END {
		for (file in plus) {
			if (file in minus) {
				print "M " file
				delete minus[file]
			} else {
				print "+ " file
			}
		}

		for (file in minus) {
			print "- " file
		}
	}

	' <<< "$1"
}

function rsync_run ()
{
	local internal_path="$1" # внутренний путь
	local external_path="$2" # внешний путь

	mkdir -p "${internal_path}"

	local current_path="${internal_path}/current"
	local named_path="${internal_path}/$(date +%Y-%m-%d_%H-%M-%S)"

	echo ''
	echo '----- ----- ----- ----- -----'
	echo ''
	echo "internal_path: ${internal_path}"
	echo "external_path: ${external_path}"

	# ===== ===== ===== deleting old backups ===== ===== =====

	echo ''
	echo '[deleting old backups]'
	echo $(find "${internal_path}" -mindepth 1 -maxdepth 1 -mtime "+${SHELF_LIFE}" -prune -print0 | xargs -0 rm -rfv)

	# ===== ===== ===== dry-run ===== ===== =====

	echo ''
	echo '[rsync dry-run]'

	local dry_run=$(rsync --dry-run --itemize-changes --archive --delete --numeric-ids --delete-excluded \
		--rsh='/usr/bin/ssh -i /home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru' \
		"${external_path}" \
		"${current_path}" | head -n 5)

	if [[ -z "${dry_run}" ]];
	then
		echo 'no changes'
		return
	fi

	echo "${dry_run}"

	# ===== ===== ===== sync ===== ===== =====

	echo ''
	echo '[rsync]'
	echo $(rsync --stats --archive --delete --numeric-ids --delete-excluded \
		--rsh='/usr/bin/ssh -i /home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru' \
		"${external_path}" \
		"${current_path}")

	cp -al "${current_path}" "${named_path}"

	# ===== ===== ===== rsnapshot-diff ===== ===== =====

	echo ''
	echo '[rsnapshot-diff]'

	local last_backup_path=$(find "${internal_path}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2- | head -n 3 | tail -n 1)
	local differences='-- empty --'

	if [[ -n "${last_backup_path}" && "${last_backup_path}" != "${named_path}" ]];
	then
		local diff=$(rsnapshot-diff -v "${last_backup_path}" "${named_path}")
		local processed_changes=$(get_changes "${diff}")

		echo "last_backup_path: ${last_backup_path}"
		echo "named_path: ${named_path}"

		printf "%s\n\n===== ===== ===== rsnapshot-diff ===== ===== =====\n\n%s" "${processed_changes}" "${diff}" > "${named_path}.diff"
	else
		echo 'tree ${named_path}'
		tree "${named_path}" > "${named_path}.diff"
	fi
}

echo ''
echo '===== ===== ===== ===== ===== ====='
echo ''
echo "STARTED: $(date '+%Y-%m-%d %H:%M:%S')"

rsync_run "${COPIES_PATH}/storage" 'koren-backup@koren2.ru:/media/koren/server/storage/'
# rsync_run "${COPIES_PATH}/backup_check" 'koren-backup@koren2.ru:~/backup_check'

echo ''
echo '----- ----- ----- ----- -----'
echo ''
echo "SECONDS: ${SECONDS}"
