#!/bin/bash

# Format: host:port:db:user:password

export PG_PATCHMANAGER_DB_HOST='zumboxdb'
export PG_PATCHMANAGER_DB_PORT=5432
export PG_PATCHMANAGER_DB='zumbox'
export PG_PATCHMANAGER_DB_USER='postgres'
export PG_PATCHMANAGER_DB_PASS='pcirulez'

export PG_PATCHMANAGER="${PG_PATCHMANAGER_DB_HOST}:${PG_PATCHMANAGER_DB_PORT}:${PG_PATCHMANAGER_DB}:${PG_PATCHMANAGER_DB_USER}:${PG_PATCHMANAGER_DB_PASS}"

export PG_GEO=('geodb:5432:geo:postgres:pcirulez')
export PG_MAIL=('maildb:5432:mail:postgres:pcirulez')
export PG_MAIL_CLUSTER=('maildb:5432:mail_1:postgres:pcirulez' \
	'maildb:5432:mail_2:postgres:pcirulez' \
	'maildb:5432:mail_3:postgres:pcirulez' \
	'maildb:5432:mail_4:postgres:pcirulez')
export PG_QUEUE=('queuedb:5432:queue:postgres:pcirulez')
export PG_ZUMBOX=('zumboxdb:5432:zumbox:postgres:pcirulez')
