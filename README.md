# Debugging PostgreSQL in VSCode

This repository demonstrates how to debug the PostgreSQL source code, including extensions and third-party extensions.

To get started, first clone the PostgreSQL source code. You can obtain it from the official repository:: https://github.com/postgres/postgres

## Setting breakpoints

Traditional breakpoints can be tricky when debugging PostgreSQL because each SQL command runs in a separate process. Since this new process is only created when the SQL command is executed, you need to attach GDB to it after it starts — which can be difficult to time correctly.

To work around this, you can add a small snippet of C code at the location where you want the debugger to stop:
```c
#include <unistd.h>
#include <signal.h>

printf("Child process's pid: %d\n", getpid());
raise(SIGSTOP);
```

This causes the process to print its PID and then send itself a `SIGSTOP` signal, pausing execution right where you placed this code. You can then attach GDB to this paused process using the printed PID, allowing you to debug exactly where you want.

## Compilation and running

Next, copy the `build.sh` script into the cloned PostgreSQL's root folder. This script configures PostgreSQL to install into a local `pginstall` directory within the source folder, avoiding the need for root permissions. By default, PostgreSQL installs files into system directories like `/usr/local/...`, which usually requires root access.

Run this command to configure the build system and set up the local installation path:
```
./build.sh configure-postgres
```

After configuration, compile the source code and install PostgreSQL into the `pginstall` folder by running:
```
./build.sh build-postgres
```

Once built and installed, you can initialize the database and start the PostgreSQL server using:
```
./build.sh init-db
./build.sh run-postgres
```

When the server is running successfully, you should see a log entry similar to:
```
2025-09-16 18:33:39.351 CEST [74480] LOG:  database system is ready to accept connections
```

## Debugging in VS Code

Once the PostgreSQL server is running, it’s ready for debugging. Run an SQL command that triggers the `SIGSTOP` signal. For example, if you’ve inserted the breakpoint-triggering code into the `cube` extension, you can run:
```
./src/bin/psql/psql -p 55432 -d postgres -c "CREATE EXTENSION IF NOT EXISTS cube;"
./src/bin/psql/psql -p 55432 -d postgres -c "SELECT cube_in('1,2,3');"
```

By default, many Linux systems restrict the ability to attach debuggers to running processes for security reasons. If you try to attach VS Code (or gdb) to a PostgreSQL backend process, you might see an error like: `Superuser access is required to attach to a process.` To fix this, temporarily disable the ptrace_scope restriction by running:
```
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
```
This command lowers the kernel’s security setting, allowing your debugger to attach to processes owned by the same user without requiring root privileges.

When the code hits the inserted "breakpoint", it will print the process PID and pause execution, like this:
```
Child process's pid: 76907
```

At this point, you can attach your debugger to that process. To do this in VS Code:

0. Copy the provided `launch.json` file into your project’s `.vscode` folder.

1. Open the Debug and Run panel and select Attach to Postgres Backend from the dropdown.

![Image](https://github.com/user-attachments/assets/4a5b9de8-32f2-4cf4-919b-451aa19467aa)

2. Start the debugger, then enter the printed PID to attach to the paused process.

![Image](https://github.com/user-attachments/assets/90139776-7c19-42e6-89d0-8b2182ae2d94)

3. You’re now attached and can step through the code from the exact point where the `SIGSTOP` was triggered.

![Image](https://github.com/user-attachments/assets/1a25fc20-f531-4006-a331-66c0652baed9)

## Third party extension

You can apply the same debugging setup to third-party extensions. In this example, we use the Mtree extension, which can be found here: https://github.com/ggombos/mtree.git

This extension contains a known bug that is fixed automatically by our `build.sh` script:
```
./build.sh download-mtree
```

Before building Mtree, insert the breakpoint-triggering C code (shown earlier) into any source files where you want to pause execution.

Then build the extension with:
```
./build.sh build-mtree
```

After building, you can initialize the database and start PostgreSQL as usual:
```
./build.sh init-db
./build.sh run-postgres
```

Finally, run the extension with these commands:
```
./src/bin/psql/psql -p 55432 -d postgres -c "CREATE EXTENSION IF NOT EXISTS mtree_gist;"
./src/bin/psql/psql -p 55432 -d postgres -c "SELECT mtree_float_array_input('1,2,3');"
```

## Purpose of the debugging

We noticed that when we print certain values in the M-Tree and run it again, we get completely different results. At first, we suspected that there might be an issue with the M-Tree code itself, but after reviewing it multiple times, we ruled that out. Still, we were curious whether PostgreSQL might be causing this behavior. To verify this, we printed some values in the Cube module—and to our surprise, we observed the same behavior there as well.

Below, you can see the command that reproduces the issue we encountered.

We added print statements in the Cube’s penalty function, so the function looked like this:
```c
Datum g_cube_penalty(PG_FUNCTION_ARGS)
{
	GISTENTRY  *origentry = (GISTENTRY *) PG_GETARG_POINTER(0);
	GISTENTRY  *newentry = (GISTENTRY *) PG_GETARG_POINTER(1);
	float	   *result = (float *) PG_GETARG_POINTER(2);
	NDBOX      *orig      = DatumGetNDBOXP(origentry->key);
	NDBOX      *newc      = DatumGetNDBOXP(newentry->key);
	NDBOX	   *ud;
	double		tmp1,
				tmp2;

	ud = cube_union_v0(DatumGetNDBOXP(origentry->key),
					   DatumGetNDBOXP(newentry->key));
	rt_cube_size(ud, &tmp1);
	rt_cube_size(DatumGetNDBOXP(origentry->key), &tmp2);
	*result = (float) (tmp1 - tmp2);
	
	/* Extract dimension and point flag */
	int orig_dim = (int)(orig->header & 0xFF);
	bool orig_point = ((orig->header >> 31) & 1);
	int new_dim = (int)(newc->header & 0xFF);
	bool new_point = ((newc->header >> 31) & 1);

	elog(INFO, "Penalty: orig dim=%d point=%d, new dim=%d point=%d, result=%f (%p)",
		orig_dim, orig_point, new_dim, new_point, *result, result);

	/* Print all coords of orig */
	for (int i = 0; i < orig_dim; i++)
	{
		double lo = orig->x[i];
		double hi = orig_point ? lo : orig->x[i + orig_dim];
		elog(INFO, "  orig[%d]: lo=%f hi=%f", i, lo, hi);
	}

	/* Print all coords of newc */
	for (int i = 0; i < new_dim; i++)
	{
		double lo = newc->x[i];
		double hi = new_point ? lo : newc->x[i + new_dim];
		elog(INFO, "  new[%d]: lo=%f hi=%f", i, lo, hi);
	}
	elog(INFO, "-----------------------------------------");

	PG_RETURN_FLOAT8(*result);
}
```

We performed an insertion and built the index structure using the following commands:
```
./build.sh init-db
./build.sh run-postgres

./bug_test_mtree.sh mtree1.txt
./bug_test_mtree.sh mtree2.txt

./bug_test_cube.sh cube1.txt
./bug_test_cube.sh cube2.txt
```

In the image below, you can see the difference in the results:
![Image](https://github.com/user-attachments/assets/dde7b971-1b9f-411c-8611-db6c709a1037)

### Experimenting with btree_gist

Building on our previous experiments, we wanted to investigate whether the bug also appears in other index types. Could it be related to GiST itself?

To explore this, we tested another index type: btree_gist. Surprisingly, the performance (penalty) of this GiST-based index was consistent across multiple runs.

The testing procedure was the same as before:
```
./build.sh init-db
./build.sh run-postgres

./bug_test_btree.sh btree1.txt
./bug_test_btree.sh btree2.txt
```

## Investigating the Call Stack

With this information in hand, we proceeded to investigate the call stack. Fortunately, VS Code makes it easy to view the call stack. Let’s take a look at it.

M-tree call stack:
```
libc.so.6!__pthread_kill_implementation(pthread_t threadid, int signo, int no_tid) (pthread_kill.c:44)
libc.so.6!__pthread_kill_internal(pthread_t threadid, int signo) (pthread_kill.c:89)
libc.so.6!__GI___pthread_kill(pthread_t threadid, int signo, int signo@entry) (pthread_kill.c:100)
libc.so.6!__GI_raise(int sig) (raise.c:26)
mtree_gist.so!mtree_float_array_penalty(FunctionCallInfo fcinfo) (./contrib/mtree/source/mtree_float_array.c:262)
FunctionCall3Coll(FmgrInfo * flinfo, Oid collation, Datum arg1, Datum arg2, Datum arg3) (./src/backend/utils/fmgr/fmgr.c:1186)
gistpenalty(GISTSTATE * giststate, int attno, GISTENTRY * orig, _Bool isNullOrig, GISTENTRY * add, _Bool isNullAdd) (./src/backend/access/gist/gistutil.c:733)
gistchoose(Relation r, Page p, IndexTuple it, GISTSTATE * giststate) (./src/backend/access/gist/gistutil.c:458)
gistdoinsert(Relation r, IndexTuple itup, Size freespace, GISTSTATE * giststate, Relation heapRel, _Bool is_build) (./src/backend/access/gist/gist.c:755)
gistBuildCallback(Relation index, ItemPointer tid, Datum * values, _Bool * isnull, _Bool tupleIsAlive, void * state) (./src/backend/access/gist/gistbuild.c:865)
heapam_index_build_range_scan(Relation heapRelation, Relation indexRelation, IndexInfo * indexInfo, _Bool allow_sync, _Bool anyvisible, _Bool progress, BlockNumber start_blockno, BlockNumber numblocks, IndexBuildCallback callback, void * callback_state, TableScanDesc scan) (./src/backend/access/heap/heapam_handler.c:1705)
table_index_build_scan(Relation table_rel, Relation index_rel, struct IndexInfo * index_info, _Bool allow_sync, _Bool progress, IndexBuildCallback callback, void * callback_state, TableScanDesc scan) (./src/include/access/tableam.h:1751)
gistbuild(Relation heap, Relation index, IndexInfo * indexInfo) (./src/backend/access/gist/gistbuild.c:313)
index_build(Relation heapRelation, Relation indexRelation, IndexInfo * indexInfo, _Bool isreindex, _Bool parallel) (./src/backend/catalog/index.c:3078)
index_create(Relation heapRelation, const char * indexRelationName, Oid indexRelationId, Oid parentIndexRelid, Oid parentConstraintId, RelFileNumber relFileNumber, IndexInfo * indexInfo, const List * indexColNames, Oid accessMethodId, Oid tableSpaceId, const Oid * collationIds, const Oid * opclassIds, const Datum * opclassOptions, const int16 * coloptions, const NullableDatum * stattargets, Datum reloptions, bits16 flags, bits16 constr_flags, _Bool allow_system_table_mods, _Bool is_internal, Oid * constraintId) (./src/backend/catalog/index.c:1278)
DefineIndex(Oid tableId, IndexStmt * stmt, Oid indexRelationId, Oid parentIndexId, Oid parentConstraintId, int total_parts, _Bool is_alter_table, _Bool check_rights, _Bool check_not_in_use, _Bool skip_build, _Bool quiet) (./src/backend/commands/indexcmds.c:1245)
ProcessUtilitySlow(ParseState * pstate, PlannedStmt * pstmt, const char * queryString, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:1536)
standard_ProcessUtility(PlannedStmt * pstmt, const char * queryString, _Bool readOnlyTree, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:1060)
ProcessUtility(PlannedStmt * pstmt, const char * queryString, _Bool readOnlyTree, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:523)
PortalRunUtility(Portal portal, PlannedStmt * pstmt, _Bool isTopLevel, _Bool setHoldSnapshot, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:1153)
PortalRunMulti(Portal portal, _Bool isTopLevel, _Bool setHoldSnapshot, DestReceiver * dest, DestReceiver * altdest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:1310)
PortalRun(Portal portal, long count, _Bool isTopLevel, DestReceiver * dest, DestReceiver * altdest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:788)
exec_simple_query(const char * query_string) (./src/backend/tcop/postgres.c:1278)
PostgresMain(const char * dbname, const char * username) (./src/backend/tcop/postgres.c:4774)
BackendMain(const void * startup_data, size_t startup_data_len) (./src/backend/tcop/backend_startup.c:124)
postmaster_child_launch(BackendType child_type, int child_slot, const void * startup_data, size_t startup_data_len, ClientSocket * client_sock) (./src/backend/postmaster/launch_backend.c:292)
BackendStartup(ClientSocket * client_sock) (./src/backend/postmaster/postmaster.c:3590)
ServerLoop() (./src/backend/postmaster/postmaster.c:1705)
PostmasterMain(int argc, char ** argv) (./src/backend/postmaster/postmaster.c:1403)
main(int argc, char ** argv) (./src/backend/main/main.c:231)
```

Cube call stack:
```
libc.so.6!__pthread_kill_implementation(pthread_t threadid, int signo, int no_tid) (pthread_kill.c:44)
libc.so.6!__pthread_kill_internal(pthread_t threadid, int signo) (pthread_kill.c:89)
libc.so.6!__GI___pthread_kill(pthread_t threadid, int signo, int signo@entry) (pthread_kill.c:100)
libc.so.6!__GI_raise(int sig) (raise.c:26)
cube.so!g_cube_penalty(FunctionCallInfo fcinfo) (./contrib/cube/cube.c:510)
FunctionCall3Coll(FmgrInfo * flinfo, Oid collation, Datum arg1, Datum arg2, Datum arg3) (./src/backend/utils/fmgr/fmgr.c:1186)
gistpenalty(GISTSTATE * giststate, int attno, GISTENTRY * orig, _Bool isNullOrig, GISTENTRY * add, _Bool isNullAdd) (./src/backend/access/gist/gistutil.c:733)
gistchoose(Relation r, Page p, IndexTuple it, GISTSTATE * giststate) (./src/backend/access/gist/gistutil.c:458)
gistdoinsert(Relation r, IndexTuple itup, Size freespace, GISTSTATE * giststate, Relation heapRel, _Bool is_build) (./src/backend/access/gist/gist.c:755)
gistBuildCallback(Relation index, ItemPointer tid, Datum * values, _Bool * isnull, _Bool tupleIsAlive, void * state) (./src/backend/access/gist/gistbuild.c:865)
heapam_index_build_range_scan(Relation heapRelation, Relation indexRelation, IndexInfo * indexInfo, _Bool allow_sync, _Bool anyvisible, _Bool progress, BlockNumber start_blockno, BlockNumber numblocks, IndexBuildCallback callback, void * callback_state, TableScanDesc scan) (./src/backend/access/heap/heapam_handler.c:1705)
table_index_build_scan(Relation table_rel, Relation index_rel, struct IndexInfo * index_info, _Bool allow_sync, _Bool progress, IndexBuildCallback callback, void * callback_state, TableScanDesc scan) (./src/include/access/tableam.h:1751)
gistbuild(Relation heap, Relation index, IndexInfo * indexInfo) (./src/backend/access/gist/gistbuild.c:313)
index_build(Relation heapRelation, Relation indexRelation, IndexInfo * indexInfo, _Bool isreindex, _Bool parallel) (./src/backend/catalog/index.c:3078)
index_create(Relation heapRelation, const char * indexRelationName, Oid indexRelationId, Oid parentIndexRelid, Oid parentConstraintId, RelFileNumber relFileNumber, IndexInfo * indexInfo, const List * indexColNames, Oid accessMethodId, Oid tableSpaceId, const Oid * collationIds, const Oid * opclassIds, const Datum * opclassOptions, const int16 * coloptions, const NullableDatum * stattargets, Datum reloptions, bits16 flags, bits16 constr_flags, _Bool allow_system_table_mods, _Bool is_internal, Oid * constraintId) (./src/backend/catalog/index.c:1278)
DefineIndex(Oid tableId, IndexStmt * stmt, Oid indexRelationId, Oid parentIndexId, Oid parentConstraintId, int total_parts, _Bool is_alter_table, _Bool check_rights, _Bool check_not_in_use, _Bool skip_build, _Bool quiet) (./src/backend/commands/indexcmds.c:1245)
ProcessUtilitySlow(ParseState * pstate, PlannedStmt * pstmt, const char * queryString, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:1536)
standard_ProcessUtility(PlannedStmt * pstmt, const char * queryString, _Bool readOnlyTree, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:1060)
ProcessUtility(PlannedStmt * pstmt, const char * queryString, _Bool readOnlyTree, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:523)
PortalRunUtility(Portal portal, PlannedStmt * pstmt, _Bool isTopLevel, _Bool setHoldSnapshot, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:1153)
PortalRunMulti(Portal portal, _Bool isTopLevel, _Bool setHoldSnapshot, DestReceiver * dest, DestReceiver * altdest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:1310)
PortalRun(Portal portal, long count, _Bool isTopLevel, DestReceiver * dest, DestReceiver * altdest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:788)
exec_simple_query(const char * query_string) (./src/backend/tcop/postgres.c:1278)
PostgresMain(const char * dbname, const char * username) (./src/backend/tcop/postgres.c:4774)
BackendMain(const void * startup_data, size_t startup_data_len) (./src/backend/tcop/backend_startup.c:124)
postmaster_child_launch(BackendType child_type, int child_slot, const void * startup_data, size_t startup_data_len, ClientSocket * client_sock) (./src/backend/postmaster/launch_backend.c:292)
BackendStartup(ClientSocket * client_sock) (./src/backend/postmaster/postmaster.c:3590)
ServerLoop() (./src/backend/postmaster/postmaster.c:1705)
PostmasterMain(int argc, char ** argv) (./src/backend/postmaster/postmaster.c:1403)
main(int argc, char ** argv) (./src/backend/main/main.c:231)
```

B-tree call stack:
```
libc.so.6!__pthread_kill_implementation(pthread_t threadid, int signo, int no_tid) (pthread_kill.c:44)
libc.so.6!__pthread_kill_internal(pthread_t threadid, int signo) (pthread_kill.c:89)
libc.so.6!__GI___pthread_kill(pthread_t threadid, int signo, int signo@entry) (pthread_kill.c:100)
libc.so.6!__GI_raise(int sig) (raise.c:26)
btree_gist.so!gbt_float8_penalty(FunctionCallInfo fcinfo) (./contrib/btree_gist/btree_float8.c:201)
FunctionCall3Coll(FmgrInfo * flinfo, Oid collation, Datum arg1, Datum arg2, Datum arg3) (./src/backend/utils/fmgr/fmgr.c:1186)
gistpenalty(GISTSTATE * giststate, int attno, GISTENTRY * orig, _Bool isNullOrig, GISTENTRY * add, _Bool isNullAdd) (./src/backend/access/gist/gistutil.c:733)
findDontCares(Relation r, GISTSTATE * giststate, GISTENTRY * valvec, GistSplitVector * spl, int attno) (./src/backend/access/gist/gistsplit.c:132)
gistUserPicksplit(Relation r, GistEntryVector * entryvec, int attno, GistSplitVector * v, IndexTuple * itup, int len, GISTSTATE * giststate) (./src/backend/access/gist/gistsplit.c:506)
gistSplitByKey(Relation r, Page page, IndexTuple * itup, int len, GISTSTATE * giststate, GistSplitVector * v, int attno) (./src/backend/access/gist/gistsplit.c:697)
gistSplit(Relation r, Page page, IndexTuple * itup, int len, GISTSTATE * giststate) (./src/backend/access/gist/gist.c:1483)
gist_indexsortbuild_levelstate_flush(GISTBuildState * state, GistSortedBuildLevelState * levelstate) (./src/backend/access/gist/gistbuild.c:524)
gist_indexsortbuild_levelstate_add(GISTBuildState * state, GistSortedBuildLevelState * levelstate, IndexTuple itup) (./src/backend/access/gist/gistbuild.c:477)
gist_indexsortbuild(GISTBuildState * state) (./src/backend/access/gist/gistbuild.c:422)
gistbuild(Relation heap, Relation index, IndexInfo * indexInfo) (./src/backend/access/gist/gistbuild.c:283)
index_build(Relation heapRelation, Relation indexRelation, IndexInfo * indexInfo, _Bool isreindex, _Bool parallel) (./src/backend/catalog/index.c:3078)
index_create(Relation heapRelation, const char * indexRelationName, Oid indexRelationId, Oid parentIndexRelid, Oid parentConstraintId, RelFileNumber relFileNumber, IndexInfo * indexInfo, const List * indexColNames, Oid accessMethodId, Oid tableSpaceId, const Oid * collationIds, const Oid * opclassIds, const Datum * opclassOptions, const int16 * coloptions, const NullableDatum * stattargets, Datum reloptions, bits16 flags, bits16 constr_flags, _Bool allow_system_table_mods, _Bool is_internal, Oid * constraintId) (./src/backend/catalog/index.c:1278)
DefineIndex(Oid tableId, IndexStmt * stmt, Oid indexRelationId, Oid parentIndexId, Oid parentConstraintId, int total_parts, _Bool is_alter_table, _Bool check_rights, _Bool check_not_in_use, _Bool skip_build, _Bool quiet) (./src/backend/commands/indexcmds.c:1245)
ProcessUtilitySlow(ParseState * pstate, PlannedStmt * pstmt, const char * queryString, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:1536)
standard_ProcessUtility(PlannedStmt * pstmt, const char * queryString, _Bool readOnlyTree, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:1060)
ProcessUtility(PlannedStmt * pstmt, const char * queryString, _Bool readOnlyTree, ProcessUtilityContext context, ParamListInfo params, QueryEnvironment * queryEnv, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/utility.c:523)
PortalRunUtility(Portal portal, PlannedStmt * pstmt, _Bool isTopLevel, _Bool setHoldSnapshot, DestReceiver * dest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:1153)
PortalRunMulti(Portal portal, _Bool isTopLevel, _Bool setHoldSnapshot, DestReceiver * dest, DestReceiver * altdest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:1310)
PortalRun(Portal portal, long count, _Bool isTopLevel, DestReceiver * dest, DestReceiver * altdest, QueryCompletion * qc) (./src/backend/tcop/pquery.c:788)
exec_simple_query(const char * query_string) (./src/backend/tcop/postgres.c:1278)
PostgresMain(const char * dbname, const char * username) (./src/backend/tcop/postgres.c:4774)
BackendMain(const void * startup_data, size_t startup_data_len) (./src/backend/tcop/backend_startup.c:124)
postmaster_child_launch(BackendType child_type, int child_slot, const void * startup_data, size_t startup_data_len, ClientSocket * client_sock) (./src/backend/postmaster/launch_backend.c:292)
BackendStartup(ClientSocket * client_sock) (./src/backend/postmaster/postmaster.c:3590)
ServerLoop() (./src/backend/postmaster/postmaster.c:1705)
PostmasterMain(int argc, char ** argv) (./src/backend/postmaster/postmaster.c:1403)
main(int argc, char ** argv) (./src/backend/main/main.c:231)
```

Looking at the differences, we can see that the M-tree and the Cube share the same call stack. In contrast, the B-tree exhibits a slightly different call stack.

Cube vs M-tree differences:
![Image](https://github.com/user-attachments/assets/8bd9440f-c103-43ad-907d-e494f5d924b7)

B-tree vs Cube differences:
![Image](https://github.com/user-attachments/assets/3ad4d5d7-150f-4801-ac78-67668683ba37)
