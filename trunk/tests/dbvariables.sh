#!/bin/bash

# Format: host:port:db:user:password

export PG_PATCHMANAGER_DB_HOST='ztest01'
export PG_PATCHMANAGER_DB_PORT=5432
export PG_PATCHMANAGER_DB='testmanager'
export PG_PATCHMANAGER_DB_USER='pirulo'
export PG_PATCHMANAGER_DB_PASS=''

export PG_PATCHMANAGER="${PG_PATCHMANAGER_DB_HOST}:${PG_PATCHMANAGER_DB_PORT}:${PG_PATCHMANAGER_DB}:${PG_PATCHMANAGER_DB_USER}:${PG_PATCHMANAGER_DB_PASS}"

export PG_TESTDB1=('ztest01:5432:testdb11:pirulo:' \
	'ztest01:5432:testdb12:pirulo:')
export PG_TESTDB2=('ztest02:5432:testdb21:postgres:coquito' \
	'ztest02:5432:testdb22:postgres:coquito')
