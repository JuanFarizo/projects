# JVM Connection Methods

Implementation order.

## 1. Local attach
`VirtualMachine.attach(pid)` + `startLocalManagementAgent()`.

## 2. Direct remote JMX
Target JVM flags: `.port=9010` `.rmi.port=9010` `-Djava.rmi.server.hostname=<reachable IP>`.

## 3. SSH -L tunnel
`ssh -L 9010:localhost:9010 -L 9011:localhost:9011 user@host`
Target flags: `.rmi.port=9011` `-Djava.rmi.server.hostname=localhost`.

## 4. SSH SOCKS proxy
`ssh -D 9696 user@host`
Client flags: `-DsocksProxyHost=localhost -DsocksProxyPort=9696`.

## 5. SSH + jcmd/jstat
`ssh user@host jcmd <pid> GC.heap_info`. No JMX involved.

## 6. Docker, local
`docker run -p 9010:9010 -p 9011:9011 --label jvm-monitor.enabled=true`
Target flags: `.rmi.port=9011` `-Djava.rmi.server.hostname=localhost`.

No tunnel — discovery only. Discovery: Docker Engine API over the daemon's Unix socket (`DOCKER_HOST`-aware), filtered
server-side to `label=jvm-monitor.enabled=true`.
