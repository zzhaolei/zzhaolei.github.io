+++
title = '通过docker配置MySQL主从服务'
date = 2024-09-01T10:13:00+08:00
tags = [ "Docker", "MySQL" ]
draft = false
+++

## 目录结构

```go
.
├── master
│  └── my.cnf
├── slave
│  └── my.cnf
└── docker-compose.yml
```

`master`：主配置

`slave`：从配置

`docker-compose`：通过 docker-compose 进行容器配置和启动

**master/my.cnf**

```go
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/8.3/en/server-configuration-defaults.html

[mysqld]
host-cache-size=0
skip-name-resolve
datadir=/var/lib/mysql
socket=/var/run/mysqld/mysqld.sock
secure-file-priv=/var/lib/mysql-files
user=mysql

pid-file=/var/run/mysqld/mysqld.pid

# 自定义部分
log-bin=master-bin
binlog-format=row  # row 按行重放，statement 重放 sql 语句，mixed 默认基于 statement，一旦发现基于 sql 无法精准重放时，会使用 row，MySQL 默认是基于 statement 的复制
binlog-do-db=test  # 开启 binlog 的数据库名，如果有多个数据库，那么可以重复设置
server-id=1  # server-id 不能和任何 主或从 重复
# 自定义部分

[client]
socket=/var/run/mysqld/mysqld.sock

!includedir /etc/mysql/conf.d/
```

**slave/my.cnf** 和 master/my.cnf 内容基本一致，但是 server-id 不能重复

```go
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/8.3/en/server-configuration-defaults.html

[mysqld]
host-cache-size=0
skip-name-resolve
datadir=/var/lib/mysql
socket=/var/run/mysqld/mysqld.sock
secure-file-priv=/var/lib/mysql-files
user=mysql

pid-file=/var/run/mysqld/mysqld.pid

# 自定义部分
log-bin=master-bin
binlog-format=row
binlog-do-db=test
server-id=2  # 注意不要重复
# 自定义部分

[client]
socket=/var/run/mysqld/mysqld.sock

!includedir /etc/mysql/conf.d/
```

**docker-compose.yml**

```yaml
version: '3'

# 定义一个 network，方便主从容器之间通信。名字可以随便起。
networks:
  mysql-master-slave-network:
    driver: bridge

# 定义服务
services:
  mysql-master:
    image: mysql
    container_name: mysql-master
    ports:
      - 3306:3306
    volumes:
      - "./master/:/etc/mysql/conf.d"  # 将 master 中的配置映射到容器内
    environment:
      MYSQL_ROOT_PASSWORD: root  # 设置 MySQL root 密码
    restart: unless-stopped  # 启动方式
    networks:
      - mysql-master-slave-network  # 必须指定容器的网络，不然在 bridge 模式下容器无法正确通信

  mysql-slave:
    image: mysql
    container_name: mysql_slave
    ports:
      - 3307:3306
    volumes:
      - "./slave/:/etc/mysql/conf.d"
    environment:
      MYSQL_ROOT_PASSWORD: root
    restart: unless-stopped
    networks:
      - mysql-master-slave-network
```

## 主从设置

### 获取 master 的状态

1. 连接进 `master`，然后执行查看命令

```bash
$ mycli mysql://root:root@localhost:3306
> show master status;
+-------------------+----------+--------------+------------------+-------------------+
| File              | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+-------------------+----------+--------------+------------------+-------------------+
| master-bin.000003 | 352      |              |                  |                   |
+-------------------+----------+--------------+------------------+-------------------+
```

`File` 就是当前 `binlog` 文件，`Position` 是偏移量，说明下一条命令从这里开始。`File` 和 `Position` 后面在 `slave` 中会使用到。

1. 如果没有数据库，则需要先创建一个数据库，否则 `slave` 不会正常同步。（`slave` 也需要先创建一个相同的数据库，才能开始同步）

```sql
> create database test;
Query OK, 1 row affected
Time: 0.006s
```

### 配置从库

1. 连接进 `slave`

```go
$ mycli mysql://root:root@localhost:3307
```

1. 查看 `slave` 的状态，默认应该是空的

```sql
> show slave status\G;
***************************[ 1. row ]***************************
Slave_IO_State                |
Master_Host                   |
Master_User                   |
Master_Port                   |
Connect_Retry                 |
Master_Log_File               |
Read_Master_Log_Pos           |
Relay_Log_File                |
Relay_Log_Pos                 |
Relay_Master_Log_File         |
Slave_IO_Running              |
Slave_SQL_Running             |
```

1. 创建数据库

```sql
> create database test;
Query OK, 1 row affected
Time: 0.006s
```

1. 连接到主库

```sql
> change master to master_host='mysql-master',master_user='root',master_password='root',master_port=3306,master_log_file='master-bin.000003',master_log_pos=352;
Query OK, 0 rows affected
Time: 0.017s
```

`master_host`：可以填写 `mysql-master`，因为我们已经指定了主和从都在这个网络里面，只是他们的 `ip` 不同，`docker` 会帮我们进行转发

`master_port`：是主机容器内部的端口，而不是我们映射出来的端口，因为我们是直接连接的容器内部。

`master_log_file`：就是我们看到的 master 的 FIle 信息，指定我们的 slave 从这个 binlog 开始同步

`master_log_pos`：就是我们看到的 master 的 Position 信息，指定我们的 slave 从这个偏移量开始同步

其他的配置都是 mysql 的账户信息。

1. 启动主从复制

```sql
> start slave;
Query OK, 0 rows affected
Time: 0.018s
```

查看 `slave` 状态，如果 `Slave_IO_Running` 和 `Slave_SQL_Running` 都为 `Yes`，则说明启动成功，如果有一个显示为 `No`，则可以查看 `Last_IO_Error` 或 `Last_SQL_Error` 的错误信息。

- 失败示例，可以看到 `Last_IO_Error` 字段显示主从的 `server-id` 重复了，所以启动失败

```sql
> show slave status\G
***************************[ 1. row ]***************************
Slave_IO_State                |
Master_Host                   | mysql-master
Master_User                   | root
Master_Port                   | 3306
Connect_Retry                 | 60
Master_Log_File               | master-bin.000004
Read_Master_Log_Pos           | 158
Relay_Log_File                | bce0051a5191-relay-bin.000001
Relay_Log_Pos                 | 4
Relay_Master_Log_File         | master-bin.000004
Slave_IO_Running              | No
Slave_SQL_Running             | Yes
...
Master_SSL_Verify_Server_Cert | No
Last_IO_Errno                 | 13117
Last_IO_Error                 | Fatal error: The replica I/O thread stops because source and replica have equal MySQL server ids; these ids must be different for replication to work (or the --replicate-same-server-id option must be used on replica but this does not always make sense; please check the manual before using it).
Last_SQL_Errno                | 0
Last_SQL_Error                |
Replicate_Ignore_Server_Ids   |
...
```

- 成功示例，`Slave_IO_Running` 和 `Slave_SQL_Running` 均为 Yes

```sql
> show slave status\G
***************************[ 1. row ]***************************
Slave_IO_State                | Waiting for source to send event
Master_Host                   | mysql-master
Master_User                   | root
Master_Port                   | 3306
Connect_Retry                 | 60
Master_Log_File               | master-bin.000003
Read_Master_Log_Pos           | 352
Relay_Log_File                | 89c93f9a6591-relay-bin.000002
Relay_Log_Pos                 | 329
Relay_Master_Log_File         | master-bin.000003
Slave_IO_Running              | Yes
Slave_SQL_Running             | Yes
...
Last_IO_Errno                 | 0
Last_IO_Error                 |
Last_SQL_Errno                | 0
Last_SQL_Error                |
Replicate_Ignore_Server_Ids   |
...
```

### 测试同步

1. 连接到 `master`，在 `test` 库中新建一个表

```sql
$ mycli mysql://root:root@localhost:3306
> use test;
> create table T (
->      id int primary key,
->      a int,
->      b int,
->      c int
->  )
Query OK, 0 rows affected
Time: 0.027s
```

1. 连接到 `slave`，进入 `test` 库查看所有的表，会发现自动创建了一个 T 表

```sql
$ mycli mysql://root:root@localhost:3307
> use test;
> show tables;
+-------------------+
| Tables_in_test |
+-------------------+
| T                 |
+-------------------+

1 rows in set
Time: 0.010s
```
