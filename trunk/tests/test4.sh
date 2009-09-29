#!/bin/bash

. env_var_function
declareConnections "${PG_TESTDB1[@]}" "${PG_TESTDB2[@]}"

exec_sql_and_commit '' "${PG_TESTDB1[@]}" "${PG_TESTDB2[@]}" <<EOF
  CREATE TABLE tata (
    tata int not null default 0
  );
  INSERT INTO tata VALUES (1);
  INSERT INTO tata VALUES (2);
  INSERT INTO tata VALUES (3);
EOF

exec_sql '--tuples-only' "${PG_TESTDB1[@]}" "${PG_TESTDB2[@]}" <<EOF > caca.txt
  SELECT * FROM tata;
EOF
