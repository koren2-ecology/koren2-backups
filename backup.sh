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
	local named_path
	named_path="${internal_path}/$(date +%Y-%m-%d_%H-%M-%S)"

	echo ''
	echo '----- ----- ----- ----- -----'
	echo ''
	echo "remote_ssh: ${remote_ssh}"
	echo "external_path: ${external_path}"
	echo "internal_path: ${internal_path}"

	# ===== ===== ===== deleting old backups ===== ===== =====

	echo ''
	echo '[deleting old backups]'
	find "${internal_path}" -mindepth 1 -maxdepth 1 ! -name "current" -mtime "+${SHELF_LIFE}" -prune -print0 | xargs -0 rm -rfv

	# ===== ===== ===== dry-run ===== ===== =====

	echo ''
	echo '[rsync dry-run]'

	local dry_run
	dry_run=$(rsync --dry-run --itemize-changes --archive --delete --numeric-ids --delete-excluded \
		--rsh='/usr/bin/ssh -i /home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru' \
		--exclude="${EXCLUDE_PATTERNS}" \
		"${remote_ssh}:${external_path}" \
		"${current_path}" 2>&1) # 2>&1 перенаправляет ошибки в переменную, чтобы dry_run не был пустым при падении

	local dry_run_status=$?

	if [[ ${dry_run_status} -ne 0 ]];
	then
		echo "ERROR: rsync dry-run failed with exit code ${dry_run_status}!" >&2
		echo "Details: ${dry_run}" >&2
		return ${dry_run_status}
	fi

	local dry_run_short
	dry_run_short=$(echo "${dry_run}" | head -n 5)

	if [[ -z "${dry_run_short}" ]];
	then
		echo 'no changes'
		return
	fi

	echo "${dry_run_short}"

	# ===== ===== ===== excluded ===== ===== =====

	echo ''
	echo '[excluded]'

	local excluded
	excluded=$(get_excluded "${remote_ssh}" "${external_path}")

	echo "${excluded}" > "${named_path}.excluded"
	echo "${excluded}"

	# ===== ===== ===== sync ===== ===== =====

	echo ''
	echo '[rsync]'
	rsync --stats --archive --delete --numeric-ids --delete-excluded \
		--rsh='/usr/bin/ssh -i /home/koren-backup/.ssh/id_ed25519_koren-backup_koren2_ru' \
		--exclude="${EXCLUDE_PATTERNS}" \
		"${remote_ssh}:${external_path}" \
		"${current_path}"

	cp -al "${current_path}" "${named_path}"

	# ===== ===== ===== rsnapshot-diff ===== ===== =====

	echo ''
	echo '[rsnapshot-diff]'

	local last_backup_path
	last_backup_path=$(find "${internal_path}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2- | head -n 3 | tail -n 1)

	if [[ -n "${last_backup_path}" && "${last_backup_path}" != "${named_path}" ]];
	then
		local differences
		differences=$(rsnapshot-diff -v "${last_backup_path}" "${named_path}")

		local processed_changes
		processed_changes=$(get_changes "${differences}")

		echo "last_backup_path: ${last_backup_path}"
		echo "named_path: ${named_path}"

		{
			echo "last_backup_path: ${last_backup_path}"
			echo "named_path: ${named_path}"

			printf "\n\n===== ===== ===== diff ===== ===== =====\n\n%s" "${processed_changes}"
			printf "\n\n===== ===== ===== rsnapshot-diff ===== ===== =====\n\n%s" "${differences}"
		} > "${named_path}.diff"
	else
		echo '-- empty --'
		echo "${named_path}" > "${named_path}.init"
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
