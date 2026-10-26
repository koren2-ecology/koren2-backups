#!/bin/bash

# ===== ===== ===== пользователи ===== ===== =====

function get_users_online ()
{
	local session
	local class
	local state

	# Экран входа gdm — тоже сессия, но класса greeter: человеком считаем только class=user.
	for session in $(loginctl list-sessions --no-legend | awk '{print $1}');
	do
		class=$(loginctl show-session "${session}" -p Class --value)
		state=$(loginctl show-session "${session}" -p State --value)

		if [[ ${class} == 'user' && ${state} != 'closing' ]];
		then
			loginctl show-session "${session}" -p Name --value
		fi
	done | sort -u | paste -sd ' '
}
