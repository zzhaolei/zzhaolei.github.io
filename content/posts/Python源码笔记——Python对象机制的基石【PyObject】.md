+++
title = 'Python源码笔记——Python对象机制的基石【PyObject】'
date = 2023-04-07T13:43:34+08:00
tags = [ "Python" ]
draft = false
+++

> 所有源码均基于`Python 3.11.2`

## 1.PyObject定义

```c
// 实际上没有任何东西被声明为PyObject，但是每个指向Python对象的指针都可以转换为PyObject*。
// 这是手动模拟的继承。同样的，每个指向可变大小的Python对象的指针也可以转换为PyObject*，此外，也可以转换为PyVarObject*。
typedef struct _object {
		_PyObject_HEAD_EXTRA  // 定义指针以支持所有活动堆对象的双向链表refchain

		Py_ssize_t ob_refcnt;
    PyTypeObject *ob_type;
} PyObject;
```

`Python`通过`ob_refcnt`字段实现基于引用计数的垃圾回收机制。对于某一个`对象A`，当有一个新的`PyObject*`引用`A对象`时，`A`的引用计数会增加`1`，当这个`PyObject*`引用被删除时，`A`的引用计数应当减`1`，当此字段为`0`时，进行垃圾回收（不一定会释放内存空间，`Python`中还有缓存机制）。

`_PyObject_HEAD_EXTRA`是一个宏，当编译`Python`时指定参数`--with-trace-refs`，那么`Py_TRACE_REFS` 会被定义。

```c
#ifdef Py_TRACE_REFS
/* Define pointers to support a doubly-linked list of all live heap objects. */
#define _PyObject_HEAD_EXTRA            \
    PyObject *_ob_next;           \
    PyObject *_ob_prev;

#define _PyObject_EXTRA_INIT _Py_NULL, _Py_NULL,

#else
#  define _PyObject_HEAD_EXTRA
#  define _PyObject_EXTRA_INIT
#endif
```

`ob_type`是一个结构体，对应着`Python`内部的一种特殊的对象，用来指定一个对象类型的类型对象。

## 2.定长对象和变长对象

在Python中除了`PyObject`结构体之外，还有`PyVarObject`结构体。

```c
#define PyObject_VAR_HEAD      PyVarObject ob_base;

typedef struct {
    PyObject ob_base;
    Py_ssize_t ob_size; /* Number of items in variable part */
} PyVarObject;
```

我们把不包含可变长度数据的对象称为定长对象，而字符串对象、整数对象这样包含可变长度数据的对象称为变长对象。它们的区别在于定长对象的不同对象占用的内存大小是一样的，而变长对象的不同对象占用的内存可能是不一样的。

变长对象通常是容器类型，`ob_size`这个字段实际上就是指明了变长对象中一共容纳了多少个元素，而不是字节的数量。

- 为什么整数对象是可变长度对象呢？因为在Python中，整数对象是没有位数限制的，这是一个大整数对象的实现，在整数对象的结构体`PyLongObject`定义中，使用到了`PyVarObject`，用于指定size。

## 3.为什么PyObject要定义在每一个Python对象的最开始字节中

从`PyVarObject`的定义可以看出，`PyVarObject`只是`PyObject`的一个扩展而已。因此，对于任何一个`PyVarObject`，其所占用的内存，开始部分的字节的意义和`PyObject`是一样的。换句话说，在`Python`内部，每一个对象都拥有相同的对象头部。这就使得在`Python`中，对对象的引用变得非常统一，我们只需要用一个`PyObject*`指针就可以引用任意一个对象，而不论该对象实际是一个什么对象。

这是一个简单的转换示例程序：

```c
#include <stdio.h>

struct PyObject {
    int _ob;
    int _type;
};

struct PyVarObject {
    struct PyObject ob_base;
    int ob_size;
};

// List结构体
struct PyListObject {
    struct PyVarObject ob_var;
    int ob_item;
};

// Python中的双向链表
struct refchain {
    struct PyObject *prev;
    struct PyObject *next;
};

int main() {
    struct PyListObject list =
        {
            .ob_var.ob_size = 2,
            .ob_var.ob_base._ob = 0,
            .ob_var.ob_base._type = 1,
            .ob_item = 3,
        };
    struct PyListObject *p_list = &list;

    // Object和List可以通过指针进行强转
    struct PyObject *p_ob = (struct PyObject *)(p_list);
    printf("Object: %d\n", p_ob->_ob); // Object: 0

    struct PyListObject *p_list1 = (struct PyListObject *)(p_ob);
    printf("List: %d\n", p_list1->ob_item); // List: 3
    return 0;
}
```

## 4.类型对象

当在内存中分配空间，创建对象的时候，我们需要知道申请多大的空间。显然，这不是一个定值，因为不同的对象，需要不同的空间，一个整数对象和一个字符串对象所需的空间肯定不同。

在`PyObject`中，`PyTypeObject *ob_type`字段就表示类型对象。

```c
typedef struct _typeobject {
		PyObject_VAR_HEAD
		const char *tp_name;  /* 用于打印，格式为"<moudle>.<name>" */
		Py_ssize_t tp_basicsize, tp_itemsize;  /* For allocation */

		/* Methods to implement standard operations */
    destructor tp_dealloc;
		...

		/* Method suites for standard classes */

    PyNumberMethods *tp_as_number;
    PySequenceMethods *tp_as_sequence;
    PyMappingMethods *tp_as_mapping;

		...

		hashfunc tp_hash;
		ternaryfunc tp_call;
} PyTypeObject;
```

一个`PyTypeObject`对象就是`Python`中面向对象理论中的”类“的实现。

在`PyTypeObject`的定义中，有三组非常重要的操作族，`tp_as_number、tp_as_sequence、tp_as_mapping`。它们分别指向`PyNumberMethods、PySequenceMethods、PyMappingMethods`函数族。

```c
typedef PyObject * (*binaryfunc)(PyObject *, PyObject *);

typedef struct {
    binaryfunc nb_add;
    binaryfunc nb_subtract;
    ...
} PyNumberMethods;
```

在`PyNumberMethods`中，定义了一个数值对象应该支持的操作。

对于一种类型来说，它完全可以同时定义三个函数中的所有操作。即一个对象既可以表现出数值对象的特性，也可以表现出map对象的特性。

```python
>>> class Int(int):
...     def __getitem__(self, key: str) -> str:
...         return key + str(self)
...
>>> a = Int(1)
>>> b = Int(2)
>>> print(a + b)
3
>>> a["key"]
'key1'
```

`a`是一个数值类型的对象实例，我们通过重写`__getitem__`方法，可以视为指定了`Int`在`Python`内部对应的`PyTypeObject`对象的`tp_as_mapping.mp_subcript`操作，最终`Int`的实例对象可以表现得像`map`对象一样。原因就是`PyTypeObject`允许一种类型同时指定三种不同对象的行为特性。

## 5.引用计数

类型对象是不会被析构的，因为没有人回去增加和减少类型对象的引用计数，`Python`程序启动后，类型对象就已经定义好了。

在每个对象创建的时候，`Python`会使用`_Py_NewReference(op)`宏来将对象的引用计数初始化为`1`。

当对象的引用计数等于`0`时，`Python`不一定会将内存空间释放，而是会采用内存缓冲池的机制，将不使用的对象缓存起来，增加`Python`的执行效率。我们后续介绍`Python`的缓冲机制。
