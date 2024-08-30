+++
title = '如何在Go中使用POSIX命名信号量'
date = 2024-08-30T17:18:48+08:00
author = '磊'
tags = [ "Rust" ]
draft = false
+++

`go` 本身提供的 `semaphore` 只能在同一个进程多个协程或线程间使用，无法在不同的 `go` 进程之间使用，所以本文介绍，如何使用 `go` 中的 `syscall` 来使用 `POSIX` 系统提供的`命名信号量`。

## Go 中的系统调用

在 `go` 中，系统调用是通过 `syscall` 包提供的 `Syscall` 函数来进行系统调用的，不同的系统调用有不同的 `trap`，以及`不同长度的参数`。

### trap

`go` 在 `syscall` 包中定义了大量的系统调用码，具体定义在文件`1.20.6/go/src/syscall/zsysnum_darwin_arm64.go` 。不同操作系统上，定义所使用的文件是不同的，这些定义都是通过不同系统的c 语言头文件自动生成的。比如 `linux amd64` 操作系统的定义在`1.20.6/go/src/syscall/zerrors_linux_amd64.go`。

### 不同长度的参数

`syscall` 包有 `Syscall、Syscall6` 两个函数，对应于不同的操作系统调用参数长度的情况。

`Syscall` 总共接收 `4` 个参数，第一个是 `trap` 定义，描述具体的系统调用，剩下的 `3` 个是系统调用所需的参数。

`Syscall6` 总共接收 `7` 个参数，第一个是 `trap` 定义，描述具体的系统调用，剩下的 `6` 个是系统调用所需的参数。

如果使用 `Syscall` 或 `Syscall6` 时，系统调用所需的参数不满足函数形参所需的数量，则剩下的参数`传0`。

例如，在 `POSIX` 系统上打开一个命名信号量的系统调用是:

```c
sem_t *sem_open(const char *name, int oflag, mode_t mode, unsigned int value);
```

因为系统调用的参数有 `4` 个，而 `Syscall` 接收的全部形参才 `4` 个，所以 `Syscall` 不能满足我们的需求，只能使用 `Syscall6` 这个函数。而 `Syscall6` 总共需要 `7` 个形参，其中有 `6` 个是系统调用参数，我们只有 `4` 个系统调用参数，那么剩下的 `2` 个系统调用参数，我们就可以使用 `0` 替代，例如：

```go
r1, r2, err := syscall.Syscall6(
  syscall.SYS_SEM_OPEN,
	uintptr(unsafe.Pointer(cs)),  // name
	uintptr(C.O_CREAT),  // flag
	uintptr(mode),  // mode
	uintptr(value),  // value
	0,  // 没有更多参数，使用 0
	0,
)
```

## 实现Samephore

信号量的操作主要有这么几个系统调用：`sem_open、sem_wait、sem_trywait、sem_post、sem_close、sem_unlink`。

在具体实现之前，我们先引入 `C` 头文件和定义一些结构，方便我们后续使用。

我们可以创建一个  `semaphore/semaphore.go` 的包，然后在 semaphore.go 中添加下面的代码：

```go
package semaphore

/*
#include <stdlib.h>
#include <fcntl.h>
*/
import "C"

import (
	"fmt"
	"syscall"
	"unsafe"
)

// Semaphore 是一个用来保存 信号描述符 的结构体
type Semaphore struct {
	sd uintptr
}

// New 创建一个空的信号量结构体
func New() *Semaphore {
	return &Semaphore{}
}
```

下文中涉及到的 `Go` 代码，均在 `semaphore.go` 文件中。

### sem_open

**POSIX 系统调用：**

```c
#include <semaphore.h>

sem_t *
sem_open(const char *name, int oflag, mode_t mode, unsigned int value);
```

获取一个 `sem_t` 值，这个值就是一个`文件描述符`，代表一个被打开的信号量。

**Go 调用：**

```go
func (sem *Semaphore) Open(name string, mode int, value int) error {
  // 将 go 字符串转为 C 字符串
	cs := C.CString(name)
  // C.CString 会在 C 侧重新申请内存，所以需要在使用后释放(在 stdlib.h 中)
	defer C.free(unsafe.Pointer(cs))

	// 调用 sem_open 系统调用，传递必须参数
	// C.O_CREAT 表示创建(在 fcntl.h 中)，value 是信号量的值，mode 为打开的 信号描述符 的状态
	r1, _, err := syscall.Syscall6(
		syscall.SYS_SEM_OPEN,
		uintptr(unsafe.Pointer(cs)),
		uintptr(C.O_CREAT),
		uintptr(mode),
		uintptr(value),
		0,
		0,
	)
	if err != 0 {
		sem.Unlink(name)
		return fmt.Errorf("create semaphore failed: %s", err)
	}
	sem.sd = r1
	return nil
}
```

### sem_trywait 和 sem_wait

**POSIX 系统调用：**

```c
#include <semaphore.h>

int
sem_trywait(sem_t *sem);

int
sem_wait(sem_t *sem);
```

`sem_trywait` 当 `sem` 的值为 `0` 时，此操作不会阻塞等待，而是会立即返回。

`sem_wait` 当 `sem` 的值为 `0` 时，此操作会阻塞等待，直到能获取信号量或者调用被中断。

这两个操作都会 `locked sem`，并且操作结果相当于 `sem` 值`减一`。

**Go 调用：**

```go
func (sem *Semaphore) TryAcquire() error {
	_, _, err := syscall.Syscall(syscall.SYS_SEM_TRYWAIT, sem.sd, 0, 0)
	if err != 0 {
		return fmt.Errorf("try acquire failed: %s", err.Error())
	}
	return nil
}

func (sem *Semaphore) Acquire() {
	_, _, _ = syscall.Syscall(syscall.SYS_SEM_WAIT, sem.sd, 0, 0)
}
```

### sem_post

**POSIX 系统调用：**

```c
#include <semaphore.h>

int
sem_post(sem_t *sem);
```

`locked sem`，对 `sem` 值`加一`，并且等待该信号量的所有`进程/线程`都会被唤醒。

**Go 调用：**

```go
func (sem *Semaphore) Release() {
	_, _, _ = syscall.Syscall(syscall.SYS_SEM_POST, sem.sd, 0, 0)
}
```

### sem_close 和 sem_unlink

**POSIX 系统调用：**

```c
#include <semaphore.h>

int
sem_close(sem_t *sem);

int
sem_unlink(const char *name);
```

`sem_close`：所引用的命名信号量关联的系统内存资源被释放，描述符无效。

`sem_unlink`：移除名为 `name` 的命名信号量。如果该信号量正在被其他进程使用，那么 `name` 将立即与该信号量解除关联，但是该信号量本身不会被移除，直到对它的所有引用都被关闭。使用 `name` 对 `sem_open()` 的后续调用将引用或创建一个名为 `name` 的新信号量。

**Go 调用：**

```go
func (sem *Semaphore) Unlink(name string) {
	cs := C.CString(name)
	defer C.free(unsafe.Pointer(cs))

	sem.close()
	_, _, _ = syscall.Syscall(syscall.SYS_SEM_UNLINK, uintptr(unsafe.Pointer(cs)), 0, 0)
}

func (sem *Semaphore) close() {
	_, _, _ = syscall.Syscall(syscall.SYS_SEM_CLOSE, sem.sd, 0, 0)
}
```
