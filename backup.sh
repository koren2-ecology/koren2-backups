#!/bin/bash

EXCLUDE_PATTERNS='??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????*'
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

function get_excluded ()
{
	local remote_ssh="$1" # удаленный ssh
	local external_path="$2" # внешний путь

	/usr/bin/ssh -i /home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru "${remote_ssh}" \
		"find ${external_path} -printf '%P\n' | \
		LC_ALL=C awk -F'/' '{
			for(i=1;i<=NF;i++) {
				if(length(\$i) > 255) {
					print length(\$i) \" символов => \" \$0
					break
				}
			}
		}'"
}

function rsync_run ()
{
	local remote_ssh="$1" # удаленный ssh
	local external_path="$2" # внешний путь
	local internal_path="$3" # внутренний путь

	mkdir -p "${internal_path}"

	local current_path="${internal_path}/current"
	local named_path="${internal_path}/$(date +%Y-%m-%d_%H-%M-%S)"

	echo ''
	echo '----- ----- ----- ----- -----'
	echo ''
	echo "remote_ssh: ${remote_ssh}"
	echo "external_path: ${external_path}"
	echo "internal_path: ${internal_path}"

	# ===== ===== ===== deleting old backups ===== ===== =====

	echo ''
	echo '[deleting old backups]'
	echo $(find "${internal_path}" -mindepth 1 -maxdepth 1 -mtime "+${SHELF_LIFE}" -prune -print0 | xargs -0 rm -rfv)

	# ===== ===== ===== excluded ===== ===== =====

	echo ''
	echo '[excluded]'

	get_excluded "${remote_ssh}" "${external_path}" > "${named_path}.excluded"

	# ===== ===== ===== dry-run ===== ===== =====

	echo ''
	echo '[rsync dry-run]'

	local dry_run=$(rsync --dry-run --itemize-changes --archive --delete --numeric-ids --delete-excluded \
		--rsh='/usr/bin/ssh -i /home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru' \
		--exclude="${EXCLUDE_PATTERNS}" \
		"${remote_ssh}:${external_path}" \
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
		--exclude="${EXCLUDE_PATTERNS}" \
		"${remote_ssh}:${external_path}" \
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

rsync_run 'koren-backup@koren2.ru' '/media/koren/server/storage/' "${COPIES_PATH}/storage"
# rsync_run 'koren-backup@koren2.ru' '~/backup_check' "${COPIES_PATH}/backup_check"

echo ''
echo '----- ----- ----- ----- -----'
echo ''
echo "SECONDS: ${SECONDS}"
