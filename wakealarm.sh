#!/bin/bash

BACKUP_HOUR='03' # час ночного копирования, на него же взводится будильник
WAKEALARM='/sys/class/rtc/rtc0/wakealarm'


# ===== ===== ===== будильник ===== ===== =====

function set_wakealarm ()
{
	local target
	target=$(date +%s -d "tomorrow ${BACKUP_HOUR}:00")

	if [[ ! -w ${WAKEALARM} ]];
	then
		echo "ОШИБКА: ${WAKEALARM} недоступен для записи." >&2
		return 1
	fi

	# Будильник одноразовый: сгорает при срабатывании и не переписывается
	# поверх взведённого, поэтому сначала сброс, потом новое значение.
	echo 0 > "${WAKEALARM}"
	echo "${target}" > "${WAKEALARM}"

	echo "Будильник взведён на $(date -d "@${target}" '+%Y-%m-%d %H:%M:%S %Z')."
}

set_wakealarm
