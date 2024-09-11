+++
title = 'Go 在 Mac 或 Linux 上构建动态库'
date = 2024-09-11T10:55:43+08:00
tags = [ "Go", "C", "zig" ]
draft = false
+++

Go 可以导出 C ABI，然后在其它兼容 C ABI 的语言中调用。

下面详细讲解一下用法：

### Go 构建动态库

1. 定义一个 go 文件，包含以下代码：

```go
package main

import "C"

//export Add
func Add(a, b int) int {
    return a + b
}

//export Multiply
func Multiply(a, b int) int {
    return a * b
}

func main() {}
```

go 的文件名称在当前示例中无关紧要，这里定义为 main.go。

main 函数是必须的，但是可以为空。

注意：代码中的 `//export Add` 表示导出 Add 函数，`export` 和 `//` 之间没有空格。这是 Go 中的一种特殊指令，类似的还有 `//go:build` 等。

1. 然后我们构建动态库：
- Linux

```bash
go build -buildmode=c-shared -o libmylib.so main.go
```

这会生成两个文件：`libmylib.so 和 libmylib.h`。

> 注意 `-o` 选项指定的名称：`libmylib.so`，在 linux 上必须这样命名动态/静态库，其中 mylib 是我们实际要使用的名称。
>
- Mac

```bash
go build -buildmode=c-shared -o libmylib.dylib main.go
```

> 注意 `-o` 选项指定的名称：`libmylib.dylib`，在 mac 上必须这样命名动态/静态库，其中 mylib 是我们实际要使用的名称。
>

> 使用 `-buildmode=c-archive` 可以构建静态链接库
>

通过这个指令，会生成两个文件：`libmylib.dylib 和 libmylib.h`，其中 `.h` 文件是我们代码中要使用的，`.dylib` 是构建二进制程序时要使用的。

### C 使用动态库

1. 定义一个 main.c 文件（名称在当前示例中无关紧要）：

```c
#include <stdio.h>
#include "libmylib.h"

int main() {
    printf("3 + 4 = %d\n", Add(3, 4));
    printf("5 * 6 = %d\n", Multiply(5, 6));
    return 0;
}
```

在 main.c 中我们引入 `libmylib.h` 头文件，并调用在 Go 中导出的函数：`Add 和 Multiply`。

1. 构建二进制程序

```bash
zig cc -o main main.c -L. -lmylib
# 等价于下面的构建脚本
# gcc -o main main.c -L. -lmylib
```

> 我们使用 zig cc 构建二进制程序，关于 zig cc 的用法和优点，可以阅读[这篇文章](https://baidu.com)。
>

上述命令会生成一个名为 main 的二进制程序，调用执行一下：

```bash
./main
# 如果 go 构建的是动态库，并且使用 gcc 编译，那么在 linux 上需要指定 lib 的路径再运行：
# LD_LIBRARY_PATH=. ./main

# Outputs:
3 + 4 = 7
5 * 6 = 30
```
