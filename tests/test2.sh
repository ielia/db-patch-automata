#!/bin/bash

. env_var_function
declareConnections "${PG_TESTDB1[@]}"

exec_sql '' "${PG_TESTDB1[@]}" <<EOF
  CREATE TABLE qq(
    f1 INT NOT NULL DEFAULT 0
  );
  INSERT INTO qq VALUES (1);
  INSERT INTO qq VALUES (2);
  INSERT INTO qq VALUES (3);
  INSERT INTO qq VALUES (4);
  SELECT * FROM qq;
EOF
