#!/bin/bash

. env_var_function
declareConnections "${PG_TESTDB1[@]}"

exec_sql '--tuples-only' "${PG_TESTDB1[@]}" <<EOF
  CREATE TABLE kk(
    f1 INT NOT NULL DEFAULT 0
  );
EOF
