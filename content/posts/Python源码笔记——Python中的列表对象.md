+++
title = 'Python源码笔记——Python中的列表对象'
date = 2023-04-07T14:00:50+08:00
tags = [ "Python" ]
draft = false
+++

## 1.列表结构体

```c
#define PyObject_VAR_HEAD      PyVarObject ob_base;

typedef struct {
    PyObject ob_base;
    Py_ssize_t ob_size; /* Number of items in variable part */
} PyVarObject;

typedef struct {
    PyObject_VAR_HEAD
    /* Vector of pointers to list elements.  list[0] is ob_item[0], etc. */
    PyObject **ob_item;

    /* ob_item contains space for 'allocated' elements.  The number
     * currently in use is ob_size.
     * Invariants:
     *     0 <= ob_size <= allocated
     *     len(list) == ob_size
     *     ob_item == NULL implies ob_size == allocated == 0
     * list.sort() temporarily sets allocated to -1 to detect mutations.
     *
     * Items must normally not be NULL, except during construction when
     * the list is not yet visible outside the function that builds it.
     */
    Py_ssize_t allocated;
} PyListObject;
```

`ob_item`是指向列表元素的指针向量，当我们通过`list[0]`获取元素时，实际上是获取的`ob_item[0]`的元素。`ob_item`的类型是`PyObject*`，由此我们可以知道，为什么`Python`中的`list`能存储任意对象的数据，这是因为任何`Python`对象都可以强转为`PyObject*`的指针类型。

`allocated`维护了`ob_item`中可容纳的元素的总数，即申请了多大的内存空间。`ob_size`是元素的数量，记录了已使用的内存空间。

- `0 ≤ ob_size ≤ allocated`
- `len(list) == ob_size`
- `ob_item == NULL`隐式等于`ob_size == allocated == 0`

当调用`list.sort()`函数时，`allocated`会被设置为`-1`。

`items`通常不能为空。

## 2.创建

```c
#ifndef PyList_MAXFREELIST
#  define PyList_MAXFREELIST 80  // 最多缓存80个
#endif

PyObject *
PyList_New(Py_ssize_t size)
{
    PyListObject *op;

    if (size < 0) {
        PyErr_BadInternalCall();
        return NULL;
    }

#if PyList_MAXFREELIST > 0
		// 从解释器中获取到缓存链表
    struct _Py_list_state *state = get_list_state();
#ifdef Py_DEBUG
		// 不能在_PyList_Fini()函数之后调用PyList_New()函数
    // PyList_New() must not be called after _PyList_Fini()
    assert(state->numfree != -1);
#endif
    if (PyList_MAXFREELIST && state->numfree) {
				// 缓存数量减1
        state->numfree--;
				// 获取最后一个缓存的PyListObject对象。
        op = state->free_list[state->numfree];
        OBJECT_STAT_INC(from_freelist);
        _Py_NewReference((PyObject *)op);
    }
    else
#endif
    {
				// 如果没有缓存，就创建一个新的对象，并通过GC创建这个对象
				//  - 容器类型，有循环引用问题，无法仅根据引用计数器回收内存
        op = PyObject_GC_New(PyListObject, &PyList_Type);
        if (op == NULL) {
            return NULL;
        }
    }

		// 如果长度为0，则说明这是一个空列表对象
    if (size <= 0) {
        op->ob_item = NULL;
    }
    else {
				// 否则就根据容量、PyObject*指针长度申请所需的内存空间
        op->ob_item = (PyObject **) PyMem_Calloc(size, sizeof(PyObject *));
        if (op->ob_item == NULL) {
            Py_DECREF(op);
						// 如果依然为NULL，则说明内存空间不足
            return PyErr_NoMemory();
        }
    }
		// 设置 ob_size，即ob->ob_size = size;
    Py_SET_SIZE(op, size);
    op->allocated = size;
		// 因为容器类型可能存在循环引用问题，所以通过gc来进行辅助的标记清除和迭代回收
    _PyObject_GC_TRACK(op);
    return (PyObject *) op;
}
```

创建函数只需要指定参数`size`，指明这个`list`的容量。

1. 在创建新的`PyListObject`对象之前，会判断是否存在缓存，并从解释器中获取（`get_list_state()`）到为`list`对象缓存的数组，然后从缓存数组`free_list`中获取最后一个缓存的`PyObject*`对象，并将这个`PyObject*`对象的引用计数加一，将`numfree`减一，。`numfree`是用来记录`free_list`中存了多少元素的。
2. 如果没有缓存或者缓存数组中还没有数据，那么就会根据`size容量`、`PyObject*指针长度`去申请内存空间，之后会设置对象`ob_size`为`size`，设置`allocated`为`size`，并使用`gc`跟中这个数组对象。
3. 最后会将`PyListObject*`对象转为`PyObject*`对象返回。

这个流程只是创建了一个具有相应内存空间的还没有存入元素的`list`对象。

## 3.添加元素

```c
int
PyList_SetItem(PyObject *op, Py_ssize_t i,
               PyObject *newitem)
{
    PyObject **p;
		// 校验是否是PyListObject的字类
    if (!PyList_Check(op)) {
				// 如果不是op不是PyListObject对象或子类，则将newitem的引用计数器减一，
				// 说明此处没有引用newitem。
				// Py_XDECREF内部会校验ob_refcnt是否为0，若为0，则调用_Py_Dealloc(op)
        Py_XDECREF(newitem);
        PyErr_BadInternalCall();
        return -1;
    }
		// valid_index就做了一件事儿，判断索引是否在0～len(op)之间
		// Py_ssize_t == long，size_t == unsigned long
		// (size_t) i < (size_t) limit
    if (!valid_index(i, Py_SIZE(op))) {
        Py_XDECREF(newitem);
        PyErr_SetString(PyExc_IndexError,
                        "list assignment index out of range");
        return -1;
    }
		// 指针移动到指定索引位置的内存首地址
    p = ((PyListObject *)op) -> ob_item + i;
		// 此处会将向p指针位置设置元素，并将旧内存位置的对象引用计数减一
    Py_XSETREF(*p, newitem);
    return 0;
}

#define Py_XSETREF(op, op2)                     \
    do {                                        \
        PyObject *_py_tmp = _PyObject_CAST(op); \
        (op) = (op2);                           \
        Py_XDECREF(_py_tmp);                    \
    } while (0)
```

1. 设置元素时主要会进行类型检查、索引检查，主要用来判断是否是`list`子类或者索引是否越界。
2. 获取指定索引内存的首地址，获取到内存中的旧对象，并设置为新的对象
3. 旧对象的引用计数减`1`，如果为`0`，则触发内存回收。

## 4.插入元素

插入元素和设置元素的逻辑不同，设置元素只需要在指定内存位置设置值，但是插入元素需要考虑到原来的元素的移动，例如：

```python
>>> l = [0, 0, 0, 0, 0]
>>> l[1] = 1
>>> l
[0, 1, 0, 0, 0]
>>> l.insert(1, 2)
>>> l
[0, 2, 1, 0, 0, 0]
```

从示例中我们可以看到，`insert`时，原本`索引1`上的`元素1`，被移动到`索引2`上了，`索引1`现在的元素是`2`。

插入元素的主要逻辑是`static int ins1(PyListObject *self, Py_ssize_t where, PyObject *v)`函数。

```c
static int
ins1(PyListObject *self, Py_ssize_t where, PyObject *v)
{
    Py_ssize_t i, n = Py_SIZE(self);
    PyObject **items;
    ...  // 检查

    assert((size_t)n + 1 < PY_SSIZE_T_MAX);
		// 保证PyListObject有足够的内存来容纳我们期望插入的元素
		// 如果内存不够，则会重新申请空间
    if (list_resize(self, n+1) < 0)
        return -1;

		// 确定插入的位置
    if (where < 0) {
        where += n;
				// 如果where小于0，则将元素插入起始位置，即索引为0
        if (where < 0)
            where = 0;
    }
		// 如果where大于n，则将元素插入列表的最后一个元素的后面，即索引为len(list)
    if (where > n)
        where = n;
		// 将items[i]的元素后移到items[i+1]的位置
    items = self->ob_item;
    for (i = n; --i >= where; )
        items[i+1] = items[i];
    Py_INCREF(v);
		// 在where索引位置设置元素
    items[where] = v;
    return 0;
}

int
PyList_Insert(PyObject *op, Py_ssize_t where, PyObject *newitem)
{
    if (!PyList_Check(op)) {
        PyErr_BadInternalCall();
        return -1;
    }
    return ins1((PyListObject *)op, where, newitem);
}
```

1. 在`ins1`函数中，为了完成元素的插入工作，必须首先确保`PyListObject`对象有足够的内存来容纳我们期望插入的元素。`Python`通过调用`list_resize`函数确保这一点。

    在`list_resize`函数中：

    - `allocated >= (n + 1) && (n + 1) >= (allocated >> 1)`，如果已申请的内存已满足使用，则将`self→ob_base→ob_size`设置为`n+1`的值
    - 重新调用`PyMem_Realloc`申请内存空间
2. 确认元素的插入点，如果`where<0`就加上`n`，`n即是len`，例如`where=-1，n=5`那么就设置`where`为`-1+5=4`的位置。如果计算完成后还`小于0`，就设置`where=0`。如果`where>n`，则将`where`设置为`n`，即在列表最后一个元素的下一个位置插入元素。

    ```python
    >>> l = [0, 0, 0, 0, 0]
    >>> l.insert(-1, 1)  // 在where=-1+5的位置插入
    >>> l
    [0, 0, 0, 0, 1, 0]
    >>> l.insert(-10, 1)  // 在where=0的位置插入
    >>> l
    [1, 0, 0, 0, 0, 1, 0]
    >>> l.insert(10, 1)  // 在where=7的位置插入
    >>> l
    [1, 0, 0, 0, 0, 1, 0, 1]
    ```

3. 将`where`到`n`之间的元素全部后移，`闭区间 [where, n]`。
4. 为要添加的`元素v`增加引用计数
5. 因为`步骤3`的操作，现在`items[where]`的位置已经没有元素了，所以`ins1`函数的最后一步就是将要添加的`元素v`设置到`where`的位置上：`items[where] = v;`。

在`Python`还有`append`函数`（PyList_Append函数）`也可以插入数据。

```c
int
_PyList_AppendTakeRefListResize(PyListObject *self, PyObject *newitem)
{
    Py_ssize_t len = PyList_GET_SIZE(self);
    assert(self->allocated == -1 || self->allocated == len);
		// 重新申请空间
    if (list_resize(self, len + 1) < 0) {
        Py_DECREF(newitem);
        return -1;
    }
		// 设置元素
    PyList_SET_ITEM(self, len, newitem);
    return 0;
}

static inline int
_PyList_AppendTakeRef(PyListObject *self, PyObject *newitem)
{
    ...  // 检查两个指针和self类型
    Py_ssize_t len = PyList_GET_SIZE(self);
    Py_ssize_t allocated = self->allocated;
    assert((size_t)len + 1 < PY_SSIZE_T_MAX);
		// 如果已申请的内存空间已经大于len，说明有多余的内存空间，直接在len位置追加元素
    if (allocated > len) {
        PyList_SET_ITEM(self, len, newitem);
        Py_SET_SIZE(self, len + 1);
        return 0;
    }
    return _PyList_AppendTakeRefListResize(self, newitem);
}

int
PyList_Append(PyObject *op, PyObject *newitem)
{
    if (PyList_Check(op) && (newitem != NULL)) {
        Py_INCREF(newitem);
        return _PyList_AppendTakeRef((PyListObject *)op, newitem);
    }
    PyErr_BadInternalCall();
    return -1;
}
```

在进行`append`操作时，也会进行内存空间的判断，如果`allocated>len`，则说明已申请内存空间大于已使用内存空间，可以直接在`len`位置追加元素。如果空间不够也会重新申请内存空间。

## 5.获取元素

```c
PyObject *
PyList_GetItem(PyObject *op, Py_ssize_t i)
{
    if (!PyList_Check(op)) {
        PyErr_BadInternalCall();
        return NULL;
    }
    if (!valid_index(i, Py_SIZE(op))) {
        _Py_DECLARE_STR(list_err, "list index out of range");
        PyErr_SetObject(PyExc_IndexError, &_Py_STR(list_err));
        return NULL;
    }
    return ((PyListObject *)op) -> ob_item[i];
}
```

获取元素时，就是直接在`PyListObject`对象的`ob_item`上进行索引对应的元素。

## 6.删除元素

1. 通过调用`list.remove(1)`函数删除对象时，对应的`C`源码是`list_remove`函数。

    在这个函数中会循环比较`ob_item`中的元素是不是和要删除的`value`一样，删除第一个相同的元素并返回。具体删除逻辑在`list_ass_slice`函数。

    ```c
    static PyObject *
    list_remove(PyListObject *self, PyObject *value)
    {
        Py_ssize_t i;

        for (i = 0; i < Py_SIZE(self); i++) {
            PyObject *obj = self->ob_item[i];
            Py_INCREF(obj);
            int cmp = PyObject_RichCompareBool(obj, value, Py_EQ);
            Py_DECREF(obj);
            if (cmp > 0) {
                if (list_ass_slice(self, i, i+1,
                                   (PyObject *)NULL) == 0)
                    Py_RETURN_NONE;
                return NULL;
            }
            else if (cmp < 0)
                return NULL;
        }
        PyErr_SetString(PyExc_ValueError, "list.remove(x): x not in list");
        return NULL;
    }
    ```

2. `list_ass_slice`对应了两种操作：
    1. `a[ilow:ihigh] = v if v != NULL`
    2. `del a[ilow:ihigh] if v == NULL`

    当调用`list.remove(1)`时，`v = NULL`，所以这是对应的删除操作。

    在`list_ass_slice`函数中进行元素删除动作时，实际上是通过`memmove`和`memcpy`来实现的。


## 7.缓存机制

前面我们已经看到了`free_list`，而`free_list`是在`Python`解释器启动的时候创建的，那么`free_list`中缓存的对象时什么时候添加的呢？答案是在`PyListObject`销毁过程中。`PyListObject`的销毁逻辑是在`list_dealloc`函数中。

```c
static void
list_dealloc(PyListObject *op)
{
    Py_ssize_t i;
    PyObject_GC_UnTrack(op);
    Py_TRASHCAN_BEGIN(op, list_dealloc)
		// 将ob_item中的元素数据的引用计数减1，并释放ob_item的内存。
    if (op->ob_item != NULL) {
        /* Do it backwards, for Christian Tismer.
           There's a simple test case where somehow this reduces
           thrashing when a *very* large list is created and
           immediately deleted. */
        i = Py_SIZE(op);
        while (--i >= 0) {
            Py_XDECREF(op->ob_item[i]);
        }
        PyMem_Free(op->ob_item);
    }
#if PyList_MAXFREELIST > 0
    struct _Py_list_state *state = get_list_state();
#ifdef Py_DEBUG
    // list_dealloc() must not be called after _PyList_Fini()
    assert(state->numfree != -1);
#endif
		// 如果numfree还未满80个，则在free_list上继续缓存PyListObject对象
    if (state->numfree < PyList_MAXFREELIST && PyList_CheckExact(op)) {
        state->free_list[state->numfree++] = op;
        OBJECT_STAT_INC(to_freelist);
    }
    else
#endif
    {
				// 否则就释放PyListObject的内存
        Py_TYPE(op)->tp_free((PyObject *)op);
    }
    Py_TRASHCAN_END
}
```

1. 在`list_dealloc`函数中，第一步是先释放`ob_item`中的元素和`ob_item`的内存
2. 然后会判断`free_list`缓存是否已经存满的`PyListObject`对象
    1. 如果存满了，就直接调用`PyListObject`对象的`PyTypeObject`对象中的`tp_free`函数释放内存空间
    2. 如果未存满，则`numfree`加一，并将缓存对象放入`free_list[numfree]`位置。

当创建新的`PyListObject`对象时，会尝试从`free_list`数组中获取，这样就省去了释放内存和重新申请内存的操作。
