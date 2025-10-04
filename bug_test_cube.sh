#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

FILE="$1"

./src/bin/psql/psql -p 55432 -d postgres -c "DROP INDEX IF EXISTS kitchen_cube_index; DROP TABLE IF EXISTS public.kitchen_cube; DROP EXTENSION IF EXISTS cube;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE EXTENSION IF NOT EXISTS cube;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE TABLE IF NOT EXISTS public.kitchen_cube (                     
    id serial primary key,                                                                                                           
    point cube
);"

./src/bin/psql/psql -p 55432 -d postgres -c "COPY public.kitchen_cube (point) FROM '$(realpath ./contrib/mtree/tests/float_array/float_array_1000_cube.csv)' DELIMITER '''' CSV;"

./src/bin/psql/psql -p 55432 -d postgres -c "CREATE INDEX IF NOT EXISTS kitchen_cube_index ON public.kitchen_cube USING gist (
    point
);" &> ./my_logs/$FILE