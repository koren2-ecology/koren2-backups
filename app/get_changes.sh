#!/bin/bash

# ===== ===== ===== изменения ===== ===== =====

function get_changes ()
{
	awk '

	/^[+-]/ {
		action = substr($0, 1, 1) # Получаем первый символ (+ или -)
		path = substr($0, 3)      # Получаем путь, отсекая знак и пробел

		# sub(/[[:space:]]+$/, "", path)
		sub(/\/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\//, "/<DATETIME>/", path)

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
