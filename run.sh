#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")" || exit 1

LOCK_FILE='/run/koren2_backup.lock'


# ===== ===== ===== аргументы ===== ===== =====

FORCED='no'
POWEROFF='no'

for argument in "$@";
do
	case "${argument}" in

		--force)
			FORCED='yes'
			;;

		--poweroff)
			POWEROFF='yes'
			;;

		*)
			echo "Неизвестный аргумент: ${argument}" >&2
			echo 'Допустимые: --force    — копировать сейчас, без проверки часа' >&2
			echo '            --poweroff — выключить машину после копирования' >&2
			exit 1
			;;

	esac
done

# ===== ===== ===== процесс ===== ===== =====

exec 9> "${LOCK_FILE}"

if ! flock -n 9;
then
	echo 'Другой экземпляр уже выполняется, выход.'
	exit 0
fi

# ===== ===== ===== запуск ===== ===== =====

# Будильник взводится всегда и до копирования: даже если копирование
# упадёт, машина всё равно проснётся в следующую ночь.
# Оттуда же приходит BACKUP_HOUR.
source app/wakealarm.sh

if [[ ${FORCED} == 'no' && $(date +%H) != "${BACKUP_HOUR}" ]];
then
	echo "Копирование запускается автоматически в ${BACKUP_HOUR} часа ночи."
	exit 0
fi

# ===== ===== ===== копирование ===== ===== =====

mkdir -p logs

source app/backup.sh >> "logs/$(date +%Y-%m-%d_%H-%M-%S).log" 2>&1

echo 'Копирование завершено.'

if [[ ${POWEROFF} == 'yes' ]];
then
	echo 'Выключение.'
	systemctl poweroff --no-block
fi
