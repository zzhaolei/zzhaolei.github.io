+++
title = 'Jenkins+Git子模块自动拉取代码'
date = 2019-06-01T10:04:00+08:00
tags = [ "Jenkins" ]
draft = false
+++

## jenkins+Git子模块自动拉取代码

添加Git子模块
先克隆想要添加子模块的仓库`git clone ssh://git@ip:port/user/project.git`，这个是主目录。

进入仓库，添加子模块`git submodule add ssh://git@ip:port/user/project.git`，和主仓库不同。

`ls`查看，会有`.gitmodules`和子模块的项目名。

将生成的文件和目录push到主仓库中。

## 克隆有子模块的仓库

添加过子模块的仓库，如果想重新克隆，和普通克隆一样，不过克隆后需要在仓库目录下执行
`git submodule init`和`git submodule update`，如果不执行，子模块中会没有文件。

## 更改子模块的分支

切换到子模块目录，默认子模块是master分支，`git submodule foreach git checkout dev`，
然后使用`git submodule foreach git pull`切换分支。

需要在`jenkins`任务的`构建步骤`中添加`git submodule init`和`git submodule update`，以及上述操作（写在这两个命令后面），
`jenkins`才能拉取到代码。

## submodule可以进行tag和merge

`git submodule foreach`可以分别对子模块进行操作, 所以对所有子模块进行`tag`和`merge`操作, 就相当于对总项目进行相应的操作.
