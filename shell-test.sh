#!/bin/sh
echo "Script PID = $$"
echo "This should print the numbers one to four in order:"
echo 1
./zig-out/bin/zook -e 'echo 2' -a 'echo 4'
sleep 1
echo 3
exit 0
