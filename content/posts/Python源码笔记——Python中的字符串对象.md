+++
title = 'Python源码笔记——Python中的字符串对象'
date = 2023-04-07T13:53:00+08:00
tags = [ "Python" ]
draft = false
+++

## 1.字符串对象

在`Python3.11.2`中，字符串类型`PyUnicodeObject`的实现相当的复杂

```c
typedef struct {
    PyObject_HEAD
    Py_ssize_t length;          /* Number of code points in the string */
    Py_hash_t hash;             /* Hash value; -1 if not set */
    struct {
		...
    } state;
    wchar_t *wstr;              /* wchar_t representation (null-terminated) */
} PyASCIIObject;

typedef struct {
    PyASCIIObject _base;
    Py_ssize_t utf8_length;     /* Number of bytes in utf8, excluding the
                                 * terminating \0. */
    char *utf8;                 /* UTF-8 representation (null-terminated) */
    Py_ssize_t wstr_length;     /* Number of code points in wstr, possible
                                 * surrogates count as two code points. */
} PyCompactUnicodeObject;

typedef struct {
    PyCompactUnicodeObject _base;
    union {
        void *any;
        Py_UCS1 *latin1;
        Py_UCS2 *ucs2;
        Py_UCS4 *ucs4;
    } data;                     /* Canonical, smallest-form Unicode buffer */
} PyUnicodeObject;
```

类型对象

```c
PyTypeObject PyUnicode_Type = {
    PyVarObject_HEAD_INIT(&PyType_Type, 0)
    "str",                        /* tp_name */
    sizeof(PyUnicodeObject),      /* tp_basicsize */
    0,                            /* tp_itemsize */
    /* Slots */
    (destructor)unicode_dealloc,  /* tp_dealloc */
		...
    unicode_repr,                 /* tp_repr */
    &unicode_as_number,           /* tp_as_number */
    &unicode_as_sequence,         /* tp_as_sequence */
    &unicode_as_mapping,          /* tp_as_mapping */
		...
    (reprfunc) unicode_str,       /* tp_str */
		...
    unicode_doc,                  /* tp_doc */
		...
    0,                            /* tp_init */
    0,                            /* tp_alloc */
    unicode_new,                  /* tp_new */
    PyObject_Del,                 /* tp_free */
};
```

## 2.创建

创建字符串时会进行判断，如果长度为`0`，就会使用解释器启动时初始化好的字符串对象。

```c
PyObject *
PyUnicode_New(Py_ssize_t size, Py_UCS4 maxchar)
{
    /* Optimization for empty strings */
    if (size == 0) {
        return unicode_new_empty();
    }

    PyObject *obj;
    PyCompactUnicodeObject *unicode;
    void *data;
    enum PyUnicode_Kind kind;
    int is_sharing, is_ascii;
    Py_ssize_t char_size;
    Py_ssize_t struct_size;

    ...

    /* Ensure we won't overflow the size. */
    if (size < 0) {
        PyErr_SetString(PyExc_SystemError,
                        "Negative size passed to PyUnicode_New");
        return NULL;
    }
    if (size > ((PY_SSIZE_T_MAX - struct_size) / char_size - 1))
        return PyErr_NoMemory();

    /* Duplicated allocation code from _PyObject_New() instead of a call to
     * PyObject_New() so we are able to allocate space for the object and
     * it's data buffer.
     */
    obj = (PyObject *) PyObject_Malloc(struct_size + (size + 1) * char_size);
    if (obj == NULL) {
        return PyErr_NoMemory();
    }
    _PyObject_Init(obj, &PyUnicode_Type);

    unicode = (PyCompactUnicodeObject *)obj;
    if (is_ascii)
        data = ((PyASCIIObject*)obj) + 1;
    else
        data = unicode + 1;
    _PyUnicode_LENGTH(unicode) = size;
    _PyUnicode_HASH(unicode) = -1;
    _PyUnicode_STATE(unicode).interned = 0;
    _PyUnicode_STATE(unicode).kind = kind;
    _PyUnicode_STATE(unicode).compact = 1;
    _PyUnicode_STATE(unicode).ready = 1;
    _PyUnicode_STATE(unicode).ascii = is_ascii;
    ...
    assert(_PyUnicode_CheckConsistency((PyObject*)unicode, 0));
    return obj;
}
```

针对仅包含`ASCII`字符的字符串对象，如果两个字符串的值相同，那么`Python`不会新开辟空间，而是直接引用同一块内存。

```bash
# 仅有ASCII
>>> a = "asdfasdfasfsdfasfsddsfadsf"
>>> b = "asdfasdfasfsdfasfsddsfadsf"
>>> id(a)
4528982496
>>> id(b)
4528982496
>>> import sys
>>> sys.getrefcount(a)
3
>>> sys.getrefcount(b)
3

# 包含中文
>>> a = "中国"
>>> b = "中国"
>>> id(a)
4528970928
>>> id(b)
4528969488
>>> sys.getrefcount(a)
2
>>> sys.getrefcount(b)
2

# 包含中文，但直接引用一个对象
>>> a = "中国"
>>> b = a
>>> id(a)
4528970928
>>> id(b)
4528970928
>>> sys.getrefcount(a)
3
>>> sys.getrefcount(b)
3
```

## 3.销毁

当销毁时，会调用`PyUnicode_Type`中的`tp_dealloc`函数，函数中会判断`state.interned`的值，如果是`1`，则将字符串的从`state.interned`中删除，并设置引用计数为`0`，最后会释放空间。

```c
static void
unicode_dealloc(PyObject *unicode)
{
#ifdef Py_DEBUG
    if (!unicode_is_finalizing() && unicode_is_singleton(unicode)) {
        _Py_FatalRefcountError("deallocating an Unicode singleton");
    }
#endif

    switch (PyUnicode_CHECK_INTERNED(unicode)) {
    case SSTATE_NOT_INTERNED:
        break;
    case SSTATE_INTERNED_MORTAL:
    {
        /* Revive the dead object temporarily. PyDict_DelItem() removes two
           references (key and value) which were ignored by
           PyUnicode_InternInPlace(). Use refcnt=3 rather than refcnt=2
           to prevent calling unicode_dealloc() again. Adjust refcnt after
           PyDict_DelItem(). */
        assert(Py_REFCNT(unicode) == 0);
        Py_SET_REFCNT(unicode, 3);
        if (PyDict_DelItem(interned, unicode) != 0) {
            _PyErr_WriteUnraisableMsg("deletion of interned string failed",
                                      NULL);
        }
        assert(Py_REFCNT(unicode) == 1);
        Py_SET_REFCNT(unicode, 0);
        break;
    }

    case SSTATE_INTERNED_IMMORTAL:
        _PyObject_ASSERT_FAILED_MSG(unicode, "Immortal interned string died");
        break;

    default:
        Py_UNREACHABLE();
    }

    if (_PyUnicode_HAS_WSTR_MEMORY(unicode)) {
        PyObject_Free(_PyUnicode_WSTR(unicode));
    }
    if (_PyUnicode_HAS_UTF8_MEMORY(unicode)) {
        PyObject_Free(_PyUnicode_UTF8(unicode));
    }
    if (!PyUnicode_IS_COMPACT(unicode) && _PyUnicode_DATA_ANY(unicode)) {
        PyObject_Free(_PyUnicode_DATA_ANY(unicode));
    }

    Py_TYPE(unicode)->tp_free(unicode);
}
```
