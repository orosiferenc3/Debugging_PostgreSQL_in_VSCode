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
