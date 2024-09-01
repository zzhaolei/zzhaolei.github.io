+++
title = 'Python源码笔记——Python中的整数对象'
date = 2023-04-07T13:45:10+08:00
tags = [ "Python" ]
draft = false
+++

## 1.整数对象

在`Python3.11.2`中，整数结构体叫做`PyLongObject`。

```c
#if PYLONG_BITS_IN_DIGIT == 30
typedef uint32_t digit;
...
#elif PYLONG_BITS_IN_DIGIT == 15
typedef unsigned short digit;
...
#else
#error "PYLONG_BITS_IN_DIGIT should be 15 or 30"
#endif

typedef struct _longobject {
		/* PyObject ob_base;
    Py_ssize_t ob_size; */
    PyObject_VAR_HEAD
    digit ob_digit[1];
} PyLongObject;
```

通过`PyObject_VAR_HEAD`我们可以确定，在新版`Python`中，整形是一个不定长对象。

通过前面的文章，我们知道，对于`Python`中的对象，与对象相关的元信息实际上都保存在与对象对应的类型对象中，对于`PyLongObject`，这个类型对象是`PyLong_Type`。

```c
PyTypeObject PyLong_Type = {
    PyVarObject_HEAD_INIT(&PyType_Type, 0)
    "int",                                      /* tp_name */
    offsetof(PyLongObject, ob_digit),           /* tp_basicsize */
    sizeof(digit),                              /* tp_itemsize */
    0,                                          /* tp_dealloc */
    0,                                          /* tp_vectorcall_offset */
    0,                                          /* tp_getattr */
    0,                                          /* tp_setattr */
    0,                                          /* tp_as_async */
    long_to_decimal_string,                     /* tp_repr */
    &long_as_number,                            /* tp_as_number */
    0,                                          /* tp_as_sequence */
    0,                                          /* tp_as_mapping */
    (hashfunc)long_hash,                        /* tp_hash */
    0,                                          /* tp_call */
    0,                                          /* tp_str */
    PyObject_GenericGetAttr,                    /* tp_getattro */
    0,                                          /* tp_setattro */
    0,                                          /* tp_as_buffer */
    Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE |
        Py_TPFLAGS_LONG_SUBCLASS |
        _Py_TPFLAGS_MATCH_SELF,               /* tp_flags */
    long_doc,                                   /* tp_doc */
    0,                                          /* tp_traverse */
    0,                                          /* tp_clear */
    long_richcompare,                           /* tp_richcompare */
    0,                                          /* tp_weaklistoffset */
    0,                                          /* tp_iter */
    0,                                          /* tp_iternext */
    long_methods,                               /* tp_methods */
    0,                                          /* tp_members */
    long_getset,                                /* tp_getset */
    0,                                          /* tp_base */
    0,                                          /* tp_dict */
    0,                                          /* tp_descr_get */
    0,                                          /* tp_descr_set */
    0,                                          /* tp_dictoffset */
    0,                                          /* tp_init */
    0,                                          /* tp_alloc */
    long_new,                                   /* tp_new */
    PyObject_Free,                              /* tp_free */
};
```

`PyLongObject`对象的各种操作（比较、运算等）实际上就是调用`PyLong_Type`中的`tp_as_number`这个结构体中定义的各种函数指针。

```c
static PyNumberMethods long_as_number = {
    (binaryfunc)long_add,       /*nb_add*/
    (binaryfunc)long_sub,       /*nb_subtract*/
    (binaryfunc)long_mul,       /*nb_multiply*/
    long_mod,                   /*nb_remainder*/
    long_divmod,                /*nb_divmod*/
    long_pow,                   /*nb_power*/
    (unaryfunc)long_neg,        /*nb_negative*/
    long_long,                  /*tp_positive*/
    (unaryfunc)long_abs,        /*tp_absolute*/
    (inquiry)long_bool,         /*tp_bool*/
    (unaryfunc)long_invert,     /*nb_invert*/
    long_lshift,                /*nb_lshift*/
    long_rshift,                /*nb_rshift*/
    long_and,                   /*nb_and*/
    long_xor,                   /*nb_xor*/
    long_or,                    /*nb_or*/
    long_long,                  /*nb_int*/
    0,                          /*nb_reserved*/
    long_float,                 /*nb_float*/
    0,                          /* nb_inplace_add */
    0,                          /* nb_inplace_subtract */
    0,                          /* nb_inplace_multiply */
    0,                          /* nb_inplace_remainder */
    0,                          /* nb_inplace_power */
    0,                          /* nb_inplace_lshift */
    0,                          /* nb_inplace_rshift */
    0,                          /* nb_inplace_and */
    0,                          /* nb_inplace_xor */
    0,                          /* nb_inplace_or */
    long_div,                   /* nb_floor_divide */
    long_true_divide,           /* nb_true_divide */
    0,                          /* nb_inplace_floor_divide */
    0,                          /* nb_inplace_true_divide */
    long_long,                  /* nb_index */
};
```

在`3.11.2`中，我们可以看到`long_add函数`不需要进行溢出检查。

```c
#define CHECK_BINOP(v,w)                                \
    do {                                                \
        if (!PyLong_Check(v) || !PyLong_Check(w))       \
            Py_RETURN_NOTIMPLEMENTED;                   \
    } while(0)

static PyObject *
long_add(PyLongObject *a, PyLongObject *b)
{
    CHECK_BINOP(a, b);
    return _PyLong_Add(a, b);
}

PyObject *
_PyLong_Add(PyLongObject *a, PyLongObject *b)
{
    if (IS_MEDIUM_VALUE(a) && IS_MEDIUM_VALUE(b)) {
        return _PyLong_FromSTwoDigits(medium_value(a) + medium_value(b));
    }

    PyLongObject *z;
    if (Py_SIZE(a) < 0) {
        if (Py_SIZE(b) < 0) {
            z = x_add(a, b);
            if (z != NULL) {
                /* x_add received at least one multiple-digit int,
                   and thus z must be a multiple-digit int.
                   That also means z is not an element of
                   small_ints, so negating it in-place is safe. */
                assert(Py_REFCNT(z) == 1);
                Py_SET_SIZE(z, -(Py_SIZE(z)));
            }
        }
        else
            z = x_sub(b, a);
    }
    else {
        if (Py_SIZE(b) < 0)
            z = x_sub(a, b);
        else
            z = x_add(a, b);
    }
    return (PyObject *)z;
}
```

## 2.创建

```c
PyObject *
PyLong_FromLong(long ival)

...

PyObject *
PyLong_FromString(const char *str, char **pend, int base)

PyObject *
PyLong_FromUnicodeObject(PyObject *u, int base)
```

我们通过`PyLong_FromLong`来了解`Python`是怎么创建一个`PyLongObject`对象的。

```c
#define IS_SMALL_INT(ival) (-_PY_NSMALLNEGINTS <= (ival) && (ival) < _PY_NSMALLPOSINTS)
typedef int32_t sdigit;

static PyObject *
get_small_int(sdigit ival)
{
    assert(IS_SMALL_INT(ival));
		// 将值转为索引，例如ival=-5，_PY_NSMALLNEGINTS + -5 == 5 + -5 == 0，即获取small_ints
		// 数组的第一个元素，也就是-5。
    PyObject *v = (PyObject *)&_PyLong_SMALL_INTS[_PY_NSMALLNEGINTS + ival];
    Py_INCREF(v);
    return v;
}

PyObject *
PyLong_FromLong(long ival)
{
    PyLongObject *v;
    unsigned long abs_ival, t;
    int ndigits;

    /* Handle small and medium cases. */
		// 小整数判断
    if (IS_SMALL_INT(ival)) {
        return get_small_int((sdigit)ival);
    }
    if (-(long)PyLong_MASK <= ival && ival <= (long)PyLong_MASK) {
        return _PyLong_FromMedium((sdigit)ival);
    }

    /* Count digits (at least two - smaller cases were handled above). */
    abs_ival = ival < 0 ? 0U-(unsigned long)ival : (unsigned long)ival;
    /* Do shift in two steps to avoid possible undefined behavior. */
    t = abs_ival >> PyLong_SHIFT >> PyLong_SHIFT;
    ndigits = 2;
    while (t) {
        ++ndigits;
        t >>= PyLong_SHIFT;
    }

    /* Construct output value. */
    v = _PyLong_New(ndigits);
    if (v != NULL) {
        digit *p = v->ob_digit;
        Py_SET_SIZE(v, ival < 0 ? -ndigits : ndigits);
        t = abs_ival;
        while (t) {
            *p++ = (digit)(t & PyLong_MASK);
            t >>= PyLong_SHIFT;
        }
    }
    return (PyObject *)v;
}
```

## 3.销毁

前面我们说过，当一个对象不再被引用时，会将引用计数器减`1`，如果引用计数器等于`0`，那么就会销毁（如果对象有缓存机制，就会缓存）对象。

针对`PyLongObject`对象，当最后一次引用`PyLongObject`的对象销毁时，会触发`PyLongObject`的销毁。

```c
static inline void Py_DECREF(PyObject *op)
{
    // Non-limited C API and limited C API for Python 3.9 and older access
    // directly PyObject.ob_refcnt.
    if (--op->ob_refcnt == 0) {
        _Py_Dealloc(op);
    }
}
#define Py_DECREF(op) Py_DECREF(_PyObject_CAST(op))
```

在`_Py_Dealloc`函数中，会调用对象的`tp_dealloc`函数用于销毁对应对象的内存`(*dealloc)(op)`。

## 4.缓存机制

`Python`为避免频繁在堆上申请和释放小整数对象的内存，使用了对象池，用于缓存小整数对象。

默认小整数池的大小为`5+257`个，区间为`[-5, 257)`，可以通过修改宏定义来修改小整数池的数量。

```c
#define _PY_NSMALLPOSINTS           257
#define _PY_NSMALLNEGINTS           5

// -5 ~ 256 = [-5, 257)
PyLongObject small_ints[_PY_NSMALLNEGINTS + _PY_NSMALLPOSINTS];
```

当`Python`解释器启动时，会自动初始化小整数池。

```c
/* The following is auto-generated by Tools/scripts/generate_global_objects.py. */
#define _Py_global_objects_INIT { \
    .singletons = { \
        .small_ints = { \
            _PyLong_DIGIT_INIT(-5), \
            _PyLong_DIGIT_INIT(-4), \
						...
				 }, \
				 ...
			}, \
}
```

以前的`Python`版本还有`free_list`用于缓存大整数对象，但是现在整数对象的实现机制改了，去除了大整数对象的缓冲机制。
