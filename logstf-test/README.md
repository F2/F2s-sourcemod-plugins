# LogsTF Test

This plugin is only used for testing the LogsTF plugin.

**Do not** install on servers.

## Instructions

1. Copy _logstf_ and _logstf-test_ to the plugins folder
2. Copy testlog.log to the /tf/ directory
3. Run the server
4. Make sure logs are enabled (`logs on`)
5. Join the server and start the match (e.g. `mp_restartgame 1`)
6. Run this rcon command: `logstf_test`
7. Set `mp_timelimit 1` to end the match
8. The log should now be uploaded to logs.tf