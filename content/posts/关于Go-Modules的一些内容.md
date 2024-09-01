+++
title = '关于Go Modules的一些内容'
date = 2019-06-01T10:08:00+08:00
tags = [ "Go" ]
draft = false
+++

## 启用Go Modules

`go mod`在`Go >= 1.13`才默认启用，在`Go >= 1.11`已经开始支持了`go mod`。

设置环境变量

```shell
# 启用go module
export GO111MODULE=on

# 设置GOPATH，开启go mod之后，这个目录主要用来存放依赖包
export GOPATH=~/go_modules

# 设置go代理，在运行go test/build等时会自动下载依赖
# 使用go get下载依赖需要在GOPATH中执行才会使用代理
export GOPROXY=https://goproxy.io
```

## go mod使用

在`$GOPATH/src`之外的任意目录创建一个目录，

```shell
mkdir -p /home/gopher/project
cd /home/gopher/project
```

这个目录就是你项目的根目录，在目录中创建mod管理文件

```shell
go mod init project
```

如果你这个项目是放在github上的，那么在创建文件的时候可以这样写，project为你github项目名称

```
go mod init github.com/YourName/project
```

`go.mod`的初始内容`cat go.mod`为:

```shell
module project

go 1.12
```

`go.mod`只需要在项目的根目录创建一次即可，在项目中`Go`会自动查找当前目录的全部`父级目录`，直到找到`go.mod`。

## 关于包的定义和自定义包的导入

- 一个目录下只能由一个定义的package

  ```
  比如在project项目中有了一个hello.go的文件，文中定义了package hello，
  这样，当你再在project中创建了一个world.go的文件，其中定义了package world会报错，无法加载package
  ```

- 每个package定义，位于一个目录中。推荐目录名和package定义的包名字相同。

  ```
  project
  ├── go.mod
  ├── hello
  │   ├── hello.go
  │   └── hello1.go
  ├── main.go
  └── world
      ├── world.go
      └── world1.go

  其中hello目录中所有文件的包定义均为package hello，hello目录中所有文件的包定义均为package world
  ```

## go mod管理

- 创建新的模块

  ```shell
  # 创建了一个新的模块，初始化 `go.mod` 文件并且生成相应的描述
  go mod init
  ```

- 添加依赖项

  ```shell
  # build，test和其它构建代码包的命令，会在需要的时候在go.mod文件中添加新的依赖项
  # 最好不要自己修改go.mod文件，因为在Go在向go.mod中添加依赖项的时候
  # 同时会向go.sum中的hash对比，确定依赖是否修改。
  go build
  go test
  ```

- 查看当前全部依赖项

  ```shell
  # 列出了当前模块所有的依赖项
  go list -m all
  ```

- 修改指定依赖项的版本（或添加一个新的依赖项）

  ```shell
  # 修改或添加
  # go get -u 会更新依赖
  # 获取指定版本的形式 go get rsc.io/sampler@v1.3.1
  go get
  ```

- 移除无用的依赖项

  ```shell
  go mod tidy
  ```
