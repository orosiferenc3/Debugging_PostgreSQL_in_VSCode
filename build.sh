#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
PG_SRC="$WORKDIR"
PG_BIN="$PG_SRC/pginstall/bin/postgres"
PG_DATA="/tmp/pgdebug_data"
PG_PORT=55432

function error_exit {
  echo "❌ Error: $1" >&2
  exit 1
}

function configure_postgres() {
  echo "⚙️ Configuring PostgreSQL..."
  cd "$PG_SRC"
  mkdir -p pginstall
  ./configure --enable-debug CFLAGS=-g --with-blocksize=32 --prefix="$(pwd)/pginstall"
  echo "✅ Configuration completed."
}

function build_postgres() {
  echo "🛠️ Building PostgreSQL..."
  cd "$PG_SRC"
  make CFLAGS='-g -O0' -j $(nproc)
  make CFLAGS='-g -O0' -j $(nproc) -C contrib
  make install
  make -C contrib install
  echo "✅ PostgreSQL build completed."
}

function clone_mtree() {
  echo "🔄 Cloning mtree repository..."
  rm -rf contrib/mtree
  git clone https://github.com/ggombos/mtree.git contrib/mtree
  
  echo "🛠️ Patching mtree extension..."
  local cmake_file="contrib/mtree/source/CMakeLists.txt"
  if [ ! -f "$cmake_file" ]; then
    error_exit "Missing CMakeLists.txt file at $cmake_file"
  fi
  sed -i \
    -e "s|set(POSTGRESQL_INCLUDE_DIR\s*\".*\")|set(POSTGRESQL_INCLUDE_DIR \"$WORKDIR/pginstall/include/server\")|" \
    -e "s|set(POSTGRESQL_EXTENSION_DIR\s*\".*\")|set(POSTGRESQL_EXTENSION_DIR \"$WORKDIR/pginstall/share/extension\")|" \
    -e "s|set(POSTGRESQL_LIBRARY_DIR\s*\".*\")|set(POSTGRESQL_LIBRARY_DIR \"$WORKDIR/pginstall/lib\")|" \
    "$cmake_file"
}

function build_install_mtree() {
  echo "🛠️ Building mtree extension..."
  mkdir -p contrib/mtree/source/build
  cd contrib/mtree/source/build
  cmake -DCMAKE_BUILD_TYPE=Debug ..
  make
  make install
  cd "$WORKDIR"
  
  echo "✅ mtree build and install completed."
}

function init_database() {
  echo "🗃️ Initializing PostgreSQL database at $PG_DATA..."
  if [ -d "$PG_DATA" ]; then
    echo "ℹ️ Removing existing data directory $PG_DATA"
    rm -rf "$PG_DATA"
  fi

  $(pwd)/pginstall/bin/initdb -D "$PG_DATA" --encoding=UTF8 --auth=trust
  echo "✅ Database initialized."
}

function run_postgres() {
  echo "🚀 Starting PostgreSQL backend on port $PG_PORT..."
  if [ ! -x "$PG_BIN" ]; then
    error_exit "Postgres backend binary not found or not executable at $PG_BIN"
  fi

  "$PG_BIN" -D "$PG_DATA" -p "$PG_PORT"
}

function usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  configure-postgres   Configure PostgreSQL to prepare building process
  build-postgres       Build PostgreSQL from source
  download-mtree       Download Mtree source code
  build-mtree          Build and install mtree extension
  init-db              Initialize PostgreSQL database
  run-postgres         Run PostgreSQL backend
  all                  Run all steps: build-postgres, build-mtree, init-db, run-postgres

You can combine multiple options, e.g.:
  $0 build-postgres build-mtree init-db run-postgres

EOF
  exit 1
}

if [ $# -eq 0 ]; then
  usage
fi

for arg in "$@"; do
  case "$arg" in
    configure-postgres)
      configure_postgres
      ;;
    build-postgres)
      build_postgres
      ;;
    download-mtree)
      clone_mtree
      ;;
    build-mtree)
      build_install_mtree
      ;;
    init-db)
      init_database
      ;;
    run-postgres)
      run_postgres
      ;;
    all)
      configure_postgres
      build_postgres
      clone_mtree
      build_install_mtree
      init_database
      run_postgres
      ;;
    *)
      echo "❓ Unknown option: $arg"
      usage
      ;;
  esac
done
