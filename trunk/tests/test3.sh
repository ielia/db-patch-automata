#!/bin/bash

. env_var_function
declareConnections "${PG_TESTDB1[@]}" "${PG_TESTDB2[@]}"

exec_sql '' "${PG_TESTDB1[@]}" "${PG_TESTDB2[@]}" <<EOF
  CREATE TABLE titi (
    tata int not null default 0
  );
  INSERT INTO titi VALUES (1);
  INSERT INTO titi VALUES (2);
  INSERT INTO titi VALUES (3);
EOF

#exec_sql '--tuples-only' "${PG_TESTDB1[@]}" "${PG_TESTDB2[@]}" <<EOF > caca.txt
#  SELECT * FROM titi;
#EOF
