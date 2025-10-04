#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

FILE="$1"

./src/bin/psql/psql -p 55432 -d postgres -c "DROP INDEX IF EXISTS kitchen_mtree_index; DROP TABLE IF EXISTS public.kitchen_mtree; DROP EXTENSION IF EXISTS mtree_gist;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE EXTENSION IF NOT EXISTS mtree_gist;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE TABLE IF NOT EXISTS public.kitchen_mtree (                     
    id serial primary key,                                                                                                           
    point mtree_float_array
);"

./src/bin/psql/psql -p 55432 -d postgres -c "COPY public.kitchen_mtree (point) FROM '$(realpath ./contrib/mtree/mtree_out_20250729_small.csv)' DELIMITER '''' CSV;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE INDEX IF NOT EXISTS kitchen_mtree_index ON public.kitchen_mtree USING gist (                                                                                                                                   
    point gist_mtree_float_array_ops (
        picksplit_strategy    = 'FirstTwo'
    )
);" &> ./my_logs/$FILE
