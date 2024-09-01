+++
title = 'Mosh连接服务器时终端颜色显示问题'
date = 2019-06-01T10:09:00+08:00
tags = [ "Shell", "Mosh" ]
draft = false
+++

在使用`mosh`连接到服务器`Ubuntu 20.04`时，发现终端(`终端是Kitty，支持256color`)的颜色不能正常显示。

使用命令查看了一下`$TERM`的设置
```shell
$ echo $TERM
xterm-256color
```
显示的是`xterm-256color`，说明配置的是没问题的。

查看`mosh`的版本：
```shell
$ mosh --version
1.3.2
```
可以看到`mosh`的版本是`1.3.2`，这个版本的`发布日期是2017-07-22`，但是`github`上`master`分支一直在开发中。

想着时间已经过去这么久了，官方应该已经解决了这个问题，毕竟现在的很多终端都是支持`256color`的，所以就在`issue`中搜索了一下，真的找到了一个解决方案。

### 定位问题

在`2017年11月23号`就有人提过关于`mosh的256color`显示支持问题，而官方也已经解决了这个问题，但是不知道为什么都已经过去这么久了还没有发布新的版本。

具体的[issue](https://github.com/mobile-shell/mosh/issues/945#issuecomment-346627355)。不过评论中说的`PPA`也已经很久没有更新了。所以我们需要新的方案解决`Linux`系统的问题。

### 解决方案

想要让`mosh`能正确的显示`256color`，就只能`手动编译mosh的master分支`。

可以查看官方的安装[教程](https://mosh.org/#getting)，包含手动编译的教程。

`记得先将之前的安装卸载掉。`

 - Mac

在`MacOS`平台上，可以使用`brew`来进行自动的编译和安装。
```shell
$ brew uninstall mosh
$ brew install --HEAD mosh
```
`Mac`在编译安装的时候，会提示更新或者安装`xcode命令行工具`，就按照`brew`执行过程中的提示操作即可。

 - Linux

在`Ubuntu 20.04`上安装，需要手动克隆`mosh`的仓库
在安装之前中，需要安装依赖，`Ubuntu`最新版本的依赖，比较少。如果你是比较旧的版本，可以参考官方的编译[教程](https://mosh.org/#getting)，里面有详细的依赖。
```shell
$ sudo apt install libncurses5-dev protobuf-compiler
```

```shell
$ git clone https://github.com/mobile-shell/mosh.git
$ cd mosh
$ ./autogen.sh
$ ./configure
$ make
$ sudo make install
```
最后执行`make install`的时候，最好添加`sudo`，因为涉及到将编译生成的可执行文件复制到系统可查找到的`bin`目录下。

### 结尾

现在再使用`mosh username@server_host`连接服务器，就可以显示`256color`了。
