#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

FILE="$1"

./src/bin/psql/psql -p 55432 -d postgres -c "DROP INDEX IF EXISTS kitchen_btree_gist_index; DROP TABLE IF EXISTS public.kitchen_btree_gist; DROP EXTENSION IF EXISTS btree_gist;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE TABLE IF NOT EXISTS public.kitchen_btree_gist (                     
    id serial primary key,                                                                                                           
    x float8,
    y float8,
    z float8
);"

./src/bin/psql/psql -p 55432 -d postgres -c "COPY public.kitchen_btree_gist (x, y, z) FROM '$(realpath ./contrib/mtree/tests/float_array/float_array_1000_btree_gist.csv)' WITH (FORMAT csv);"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE INDEX IF NOT EXISTS kitchen_btree_gist_index ON public.kitchen_btree_gist USING gist (x, y, z);" &> ./my_logs/$FILE
