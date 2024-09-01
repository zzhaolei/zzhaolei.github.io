+++
title = 'Go设计模式——开闭原则'
date = 2024-09-01T10:11:00+08:00
tags = [ "Go" ]
draft = false
+++

## 介绍

简单的说就是：`对扩展开放，对修改关闭`。对扩展开放是为了应对需求的变化，对修改关闭就是为了保证已有代码的稳定性，最终是为了让系统更具有弹性，能更好的处理需求。

开闭原则也包含了`单一职责原则`。

我们以消息队列来进行举例。

## 坏的

```go
// Package main 开闭原则 Open-Closed Principle
// 开闭原则包含了：单一职责原则
package main

import "fmt"

type KafkaQueue struct{}

func (k *KafkaQueue) SendMSG(msg string) error {
	fmt.Println("Kafka send msg success")
	return nil
}

type RabbitQueue struct{}

func (r *RabbitQueue) SendMSG(msg string) error {
	fmt.Println("Rabbitmq send msg success")
	return nil
}

type Demo struct{}

func (d *Demo) SendByKafka(queue KafkaQueue, msg string) error {
	return queue.SendMSG(msg)
}

func (d *Demo) SendByRabbit(queue RabbitQueue, msg string) error {
	return queue.SendMSG(msg)
}

func main() {
}
```

通过这个例子，我们可以看出来，这段代码违背了我们的`对扩展开放，对修改关闭`的原则。当我们需要添加一个新的RocketMQ的时候，需要改动Demo的逻辑以及其他设计的业务逻辑，可扩展性可以说是一点也没有。

## 好的

```go
// Package main 开闭原则 Open-Closed Principle
// 开闭原则包含了：单一职责原则
package main

import "fmt"

// MsgFomatter 通过Format的抽象，我们可以发送string、int、image、video等等数据类型
type MsgFomatter interface {
	Format() string
}

type Queue interface {
	SendMsg(MsgFomatter) error
}

type KafkaQueue struct{}

func (k *KafkaQueue) SendMsg(msg MsgFomatter) error {
	fmt.Printf("Kafka send msg success: %s\n", msg.Format())
	return nil
}

type RabbitQueue struct{}

func (r *RabbitQueue) SendMsg(msg MsgFomatter) error {
	fmt.Printf("Rabbitmq send msg success: %s\n", msg.Format())
	return nil
}

type RocketQueue struct{}

func (r *RocketQueue) SendMsg(msg MsgFomatter) error {
	fmt.Printf("Rocketmq send msg success: %s\n", msg.Format())
	return nil
}

type Demo struct{}

func (d *Demo) SendMsg(queue Queue, msg MsgFomatter) error {
	return queue.SendMsg(msg)
}

// MyStr 实现MsgFormatter接口，我们可以更通用的处理每一种类型
type MyStr string

func (str MyStr) Format() string {
	return string(str)
}

func main() {
	demo := Demo{}
	var s MyStr = "test"

	// kafka
	var kafka Queue = &KafkaQueue{}
	_ = demo.SendMsg(kafka, s)

	// rabbitmq
	var rabbitmq Queue = &RabbitQueue{}
	_ = demo.SendMsg(rabbitmq, s)
}
```

通过开闭原则，我们能设计出来更优雅，扩展性更好的代码。

如何在项目中灵活的运用开闭原则呢？写出支持对扩展开放，对修改关闭的代码的关键是预留扩展点，如果你开发的是一个业务导向的系统，比如人脸识别系统等，要想识别出尽可能多的扩展点，就要对业务有足够的了解，能够知道当下以及未来可能要支持的业务需求。如果是业务无关的、通用的、偏底层的系统，比如框架、组件、类库等，你需要了解它们会如何被使用，今后你打算添加哪些功能，使用者未来会有哪些更多的功能需求等等。

唯一不变的只有变化本身。我们没必要为一些遥远的、不一定的需求去提前买单，做过度的设计。
