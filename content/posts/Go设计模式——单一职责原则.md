+++
title = 'Go设计模式——单一职责原则'
date = 2024-09-01T10:10:00+08:00
tags = [ "Go" ]
draft = false
+++

## 介绍

类的职责应该是单一的，对外只提供一种功能，而引起类变化的原因应该只有一个。简单的说就是每一个类只负责自己的事情，只有单一的功能。

我们现在以银行工作人员举例：

## 坏的

```go
// Package main 单一职责原则 Single-Responsibility Principle
package main

import "fmt"

type Banker struct{}

// Save 存钱
func (b *Banker) Save(money uint64) error {
	fmt.Printf("成功存入: %d\n", money)
	return nil
}

// Transfer 转账
func (b *Banker) Transfer(money uint64, to string) error {
	fmt.Printf("成功向: %s转入: %d\n", to, money)
	return nil
}
```

单一职责原则要求一个类/接口只有一个职责，而引起类变化的原因只能有一个。

从原则上讲，我们为Banker定义存钱和转账的操作是有道理的，因为我们接口中定义的都是银行工作人员可以执行的操作，引起变化的原因只能是Banker的属性和行为发生变化。

从这方便考虑，这种设计是有合理性的，如果能保证需求不会变化或者需求变化的可能行很小，那么这种设计就是合理的。

但是实际上我们知道，需求是不断变化的，今日增加一个股票业务，那么我们就需要增加一个股票的相关属性和行为，我们的接口和实现就需要全部变动。

最好的方式就是当我们开始定义的时候，根据属性和行为进行细分，抽象不同的接口出来，在Go里面也是主张`小接口`，这样我们可以通过组合的手段来随意构造我们想要的`大接口`。

## 好的

我们将Banker进行抽象，这样可以更好的进行扩展：

```go
// Package main 单一职责原则 Single-Responsibility Principle
package main

import "fmt"

type Config struct {
	Money uint64
	To    string
}

type Banker interface {
	DoSomething(Config) error
}

type SaveBanker struct{}

func (sb *SaveBanker) DoSomething(cfg Config) error {
	fmt.Printf("成功存入: %d\n", cfg.Money)
	return nil
}

type TransferBanker struct{}

func (tb *TransferBanker) DoSomething(cfg Config) error {
	fmt.Printf("成功向: %s转入: %d\n", cfg.To, cfg.Money)
	return nil
}
```

我们抽象出来了Banker接口，每一个不太的业务员都可以实现这个接口，对行为进行自定义。

现在我们也可以增加股票的接口，来进行股票相关的业务操作，而这不会影响到其他的业务员的功能。

通过单一职责原则，我们可以更好的对代码进行扩展。

## 总结

具体问题具体分析，抽象有两种方式，一是：`自下而上的`，一是：`自上而下的`。

对于第一种，就是一开始没有细粒度的接口可以拆分，但是随着需求的演进，功能越来越复杂，这时候就可以进行自下而上的抽象了，这样抽象后也能方便我们进行灵活的开发，而不至于牵一发而动全身。

对于第二种，就是一开始就可以进行拆分，例如上文中的手机，现实中动物的体重、年龄和叫声、行为就可以进行拆分。

总而言之，了解了单一职责原则，可以帮助我们设计和阅读优秀的开源代码。
