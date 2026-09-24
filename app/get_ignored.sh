#!/bin/bash

# ===== ===== ===== игнорируемые ===== ===== =====

function get_ignored ()
{
	local remote_ssh="$1" # удаленный ssh
	local remote_key="$2" # ключ ssh
	local external_path="$3" # внешний путь

	/usr/bin/ssh -i "${remote_key}" "${remote_ssh}" \
		"find ${external_path} -printf '%P\n' | \
		LC_ALL=C awk -F'/' '{
			for(i=1;i<=NF;i++) {
				if(length(\$i) >= ${MAX_NAME_BYTES}) {
					print length(\$i) \" байт => \" \$0
					break
				}
			}
		}'"
}
