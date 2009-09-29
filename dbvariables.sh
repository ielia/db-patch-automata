#!/bin/bash

# Format: host:port:db:user:password

export PG_PATCHMANAGER_DB_HOST='managerhost'
export PG_PATCHMANAGER_DB_PORT=5432
export PG_PATCHMANAGER_DB='manager'
export PG_PATCHMANAGER_DB_USER='postgres'
export PG_PATCHMANAGER_DB_PASS=''

export PG_PATCHMANAGER="${PG_PATCHMANAGER_DB_HOST}:${PG_PATCHMANAGER_DB_PORT}:${PG_PATCHMANAGER_DB}:${PG_PATCHMANAGER_DB_USER}:${PG_PATCHMANAGER_DB_PASS}"

export PG_DBS=('db1host:5432:db1:postgres:' 'db2host:5432:db2:postgres:')
