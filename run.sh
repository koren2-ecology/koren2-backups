#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")" || exit 1

LOCK_FILE='/run/koren2_backup.lock'
STAMP_FILE='copies/latest/date_last_backup.txt'


# ===== ===== ===== процесс ===== ===== =====

exec 9> "${LOCK_FILE}"

if ! flock -n 9;
then
	echo 'Другой экземпляр уже выполняется, выход.'
	exit 0
fi

# ===== ===== ===== атрибуты ===== ===== =====

FORCED='no'

if [[ $1 == '--force' ]];
then
	FORCED='yes'
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

TODAY=$(date +%F)

if [[ ${FORCED} == 'no' && $(cat "${STAMP_FILE}" 2>/dev/null) == "${TODAY}" ]];
then
	echo "Копирование за ${TODAY} уже выполнено, повтор пропущен."
	exit 0
fi

# ===== ===== ===== копирование ===== ===== =====

mkdir -p logs

source app/backup.sh >> "logs/$(date +%Y-%m-%d_%H-%M-%S).log" 2>&1

echo "${TODAY}" > "${STAMP_FILE}"

if [[ ${FORCED} == 'yes' ]];
then
	echo 'Ручной запуск: выключение пропущено.'
	exit 0
fi

echo 'Копирование завершено, выключение.'

systemctl poweroff --no-block
