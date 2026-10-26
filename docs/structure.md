# Структура

Корень — `/mnt/backup` на koren-backup, он же корень репозитория.

```
backup/
├── app/
│   ├── backup.sh
│   ├── get_changes.sh
│   ├── get_ignored.sh
│   ├── get_users_online.sh
│   └── wakealarm.sh
├── copies/
│   └── <storage>/                  источник, сейчас один — storage
│       ├── <date>/                 снимок, имя — время запуска %Y-%m-%d_%H-%M-%S
│       │   ├── image/              сама копия: жёсткие ссылки на latest/image
│       │   ├── ignored.txt         жёсткая ссылка на latest/ignored.txt того дня
│       │   ├── changed.diff        изменения против предыдущего снимка: + / M / -
│       │   ├── rsnapshot.diff      сырой вывод rsnapshot-diff
│       │   └── config.ini          дата и время, источник, ключ, предыдущий снимок, порог длины имени
│       └── latest/
│           ├── image/              актуальная копия, в неё пишет rsync
│           ├── ignored.txt         что не скопировано из-за длины имени; при изменении пишется новым файлом
│           └── date_last_backup.txt    дата последней успешной синхронизации image/
├── docs/
│   ├── README.md
│   └── structure.md
├── logs/
│   └── <%Y-%m-%d_%H-%M-%S>.log
├── koren2_backup.service
├── koren2_backup.timer
└── run.sh
```

- `<date>` старше 180 дней удаляется целиком после очередного нового снимка, `latest` под удаление не попадает.
- Если за ночь ничего не изменилось, снимок не создаётся, но `date_last_backup.txt` обновляется — rsync прошёл, копия актуальна.
- У первого снимка нет `changed.diff` и `rsnapshot.diff`, в `config.ini` пустой `previous_path`.
