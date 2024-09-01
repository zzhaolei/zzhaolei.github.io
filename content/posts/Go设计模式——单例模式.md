+++
title = 'Go设计模式——单例模式'
date = 2024-09-01T10:12:00+08:00
tags = [ "Go" ]
draft = false
+++

## 介绍

单例模式同时解决了两个问题：

- **保证一个类只有一个实例**，例如控制某些共享资源（如数据库或文件）的访问权限
- **为该实例提供一个全局访问节点**

在`Go`中单例模式有两种实现，一种是`饿汉式`，一种是`懒汉式`。`饿汉式`简单，可以将问题及早暴露出来，`懒汉式`虽然支持延迟加载，但是也将可能的问题延迟到了第一次调用的时候，同时为了实现并发安全，也不得不加锁。

## 饿汉式

### 代码

```go
// Package singleton
package singleton

// singleton 饿汉式
var singleton *File

type File struct{}

func init() {
	singleton = &File{}
}

func GetInstance() *File {
	return singleton
}
```

### 单元测试

```go
package tests

import (
	"testing"

	"design-pattern/singleton"
	"github.com/stretchr/testify/assert"
)

// TestSingleton 测试单例
func TestInstance(t *testing.T) {
	assert.Equal(t, singleton.GetInstance(), singleton.GetInstance())
}

// BenchmarkSingleton 测试并发访问单例
func BenchmarkInstance(b *testing.B) {
	b.RunParallel(func(p *testing.PB) {
		for p.Next() {
			assert.Equal(b, singleton.GetInstance(), singleton.GetInstance())
		}
	})
}
```

## 懒汉式

### 代码

```go
// Package lazysingleton 懒汉式单例
package lazysingleton

import "sync"

var (
	lazySingleton *File
	once          sync.Once
)

type File struct{}

func GetLazyInstance() *File {
	if lazySingleton == nil {
		// 使用sync.Once来确保单例在并发时只被初始化一次
		once.Do(func() {
			lazySingleton = &File{}
		})
	}
	return lazySingleton
}
```

### 单元测试

```go
package tests

import (
	"testing"

	"design-pattern/lazysingleton"
	"github.com/stretchr/testify/assert"
)

// TestLazySingleton 测试懒汉式单例
func TestLazyInstance(t *testing.T) {
	assert.Equal(t, lazysingleton.GetLazyInstance(), lazysingleton.GetLazyInstance())
}

// BenchmarkGetLazyInstance 测试懒汉式单例
func BenchmarkGetLazyInstance(b *testing.B) {
	b.RunParallel(func(p *testing.PB) {
		for p.Next() {
			assert.Equal(b, lazysingleton.GetLazyInstance(), lazysingleton.GetLazyInstance())
		}
	})
}
```

## 测试结果

```bash
❯ go test -bench .
goos: darwin
goarch: arm64
pkg: design-pattern/tests
BenchmarkGetLazyInstance-8   	 3113553	       380.8 ns/op
BenchmarkInstance-8          	 3156261	       378.5 ns/op
PASS
ok  	design-pattern/tests	3.798s
```

根据bench结果可以发现加锁（sync.Once内部使用的atomic来进行处理）还是会对性能造成影响的，不过也在可接受范围内。
