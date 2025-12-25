+++
title = 'MySQL报错invalid Connection分析'
date = 2025-12-25T10:47:48+08:00
tags = [ "Go", "MySQL" ]
draft = true
+++

最近生产环境遇到了一个奇怪的问题，同步调用一个函数会报 `invalid connection` 错误，但是异步调用就没问题。

下面是一个最终整理出来的同步最小可复现版本：

```go
package main

import (
	"database/sql"
	"log"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

// Test 对应 test 表的结构
type Test struct {
	ID   int64
	Name string
	Age  int64
}

func main() {
	db, err := sql.Open("mysql", "root:root@tcp(127.0.0.1:3306)/demo?charset=utf8mb4&parseTime=True&loc=Asia%2FShanghai&timeout=5s&readTimeout=10s")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 设置连接池和空闲时间等
	db.SetMaxOpenConns(100)
	db.SetMaxIdleConns(50)
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetConnMaxIdleTime(10 * time.Minute)

	tx, err := db.Begin()
	if err != nil {
		log.Fatal(err)
	}

	var test Test
	test.Name = "c"
	test.Age = 1

	// A
	{
		result, err := tx.Exec("INSERT INTO test (name, age) VALUES (?, ?)", test.Name, test.Age)
		if err != nil {
			log.Fatal(err)
		}
		id, err := result.LastInsertId()
		if err != nil {
			log.Fatal(err)
		}
		test.ID = id
	}

	// B
	{
		_, err := db.Exec("UPDATE test SET name = ? WHERE id = ?", test.Name, test.ID)
		if err != nil {
			log.Fatal(err)
		}
	}

	if err := tx.Commit(); err != nil {
		log.Fatal(err)
	}
}
```

下面是 InnoDB 日志中的关键片段：

```
---TRANSACTION 40603739, ACTIVE 48 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 2 lock struct(s), heap size 1128, 1 row lock(s)
MySQL thread id 4755431, OS thread handle 140480394241792, query id 304284219 223.70.172.82 prod_rw updating
UPDATE test SET name = 'c' WHERE id = 3
------- TRX HAS BEEN WAITING 48 SEC FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 928 page no 258 n bits 120 index PRIMARY of table center.report_theater trx id 40603739 lock_mode X locks rec but not gap waiting
```

从日志可以看到，`UPDATE test SET name = 'c' WHERE id = 3` 这条语句正在等待主键行锁，且已持续 48 秒，最终触发了锁等待超时。

进一步回溯业务逻辑后发现，该阻塞并非来源于并发冲突，而是由同一逻辑链路内的事务交错使用导致的。

在代码中：
• A 使用 tx.Exec，开启了一个显式事务
• B 使用 db.Exec，MySQL 会为其开启一个隐式事务

A 在插入新记录时，会对新生成的主键行加排他锁（X 锁），并一直持有该锁直到事务提交；
而 B 随后尝试更新同一行记录时，同样需要获取这把行锁，因此只能进入等待状态。

问题的关键在于：
B 的阻塞发生在 A 提交之前，而 B 又位于 A 的执行路径中，直接阻断了 A 的提交过程。

于是便形成了一个“自阻塞”的事务结构：
A 持有锁 → B 等待锁 → A 无法提交 → B 永远无法继续执行。

⸻

这并不是传统意义上的死锁。

在死锁场景中，A 等待 B，B 也等待 A，InnoDB 可以立即检测并回滚其中一方；
而在本例中，仅存在 B 等待 A 的单向阻塞关系，InnoDB 无法将其识别为死锁，只能被动等待。

当 B 的等待时间超过 innodb_lock_wait_timeout（默认 50 秒）后，
MySQL 会主动终止该连接并返回锁等待超时错误；
在客户端侧，该连接会被标记为已失效，这也是线上`invalid connection`异常的真正来源。

回归开头，问题的根源是在同步中混用了事务和非事务连接，但是又同时锁定了同一行，导致了`自阻塞`的事务结构。但是在异步场景下，由于 B 不会阻塞 A 的提交，所以 A 可以正常的提交并释放锁，然后 B 就可以在未超时的情况下获取到锁，从而避免了`invalid connection`异常。
