+++
title = 'Rust Main 函数是如何被执行的'
date = 2024-09-01T10:20:00+08:00
tags = [ "Rust" ]
draft = false
+++

# Rust main 函数到底是如何被执行的呢？

让我们看一个关于 main 函数的示例：

```rust
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    println!("hello world");
    Ok(())
}
```

从这个示例我们可以看到，rust 的 main 函数竟然还可以返回 Result 枚举，这是为什么？rust 到底是如何执行用户定义的 main 函数的呢？

接下来让我们对 rust 的源码进行剖析，看一看 rust 到底是如何运行 main 函数的。

### Rust 运行时

首先，在几乎所有的语言中（目前我不知道哪个语言会不进行处理），在执行用户的 main 函数之前都需要进行一些初始化工作，比如分配堆栈、创建并绑定主线程、初始化通用寄存器、初始化 GC等等。

而 rust 也不例外，也会在实际调用用户执行的 main 之前进行一些初始化的操作。

你没看错，rust 也是有运行时的，只不过这个运行时没有 GC，非常的轻量级，主要是执行上面所说的初始化操作以及对 main 函数的执行和收尾。

让我们先从 `init` 开始：

```rust
// 在执行 main 之前执行
unsafe fn init(argc: isize, argv: *const *const u8, sigpipe: u8) {
    #[cfg_attr(target_os = "teeos", allow(unused_unsafe))]
    unsafe {
		    // 实际的资源初始化逻辑
        sys::init(argc, argv, sigpipe)
    };

		// 设置主线程，并设置一个名字
    let thread = Thread::new_main();
    thread::set_current(thread);
}

// 运行时只会执行一次 cleanup。
// 在 main 或程序退出的时候执行
// NOTE: 当程序被终止的时候，不能保证执行 cleanup
// （终止是 kill 等强制终止，或段错误等行为，程序无法继续执行，资源由操作系统进行回收）
pub(crate) fn cleanup() {
    static CLEANUP: Once = Once::new();
    CLEANUP.call_once(|| unsafe {
        // 刷新 stdout 缓冲区的数据，并禁用缓冲区
        crate::io::cleanup();
        // SAFETY: 通过 Once 保证，只会执行一次 cleanup
        sys::cleanup();
    });
}
```

- 系统资源的初始化和清理在 `sys::init` 和 `sys::cleanup` 中
    - `sys::init` 在 `ffi` 中不保证被调用
- `sys::init` 的源码不是算复杂，主要是保证打开标准输入输出流、初始化栈，感兴趣的可以自行阅读[源码](https://github.com/rust-lang/rust/blob/4074d4902dc19ff1bbce1d74ef9ceae15b5f41ce/library/std/src/sys/pal/unix/mod.rs#L44)

现在我们终于可以进入重点了，rust 对 main 函数的处理逻辑：

```rust
#[lang = "start"]
fn lang_start<T: crate::process::Termination + 'static>(
    main: fn() -> T,
    argc: isize,
    argv: *const *const u8,
    sigpipe: u8
) -> isize {
    let Ok(v) = lang_start_internal(
        &(move || crate::sys::backtrace::__rust_begin_short_backtrace(main).report().to_i32()),
        argc,
        argv,
        sigpipe
    );
    v
}

fn lang_start_internal(
    main: &(dyn (Fn() -> i32) + Sync + crate::panic::RefUnwindSafe),
    argc: isize,
    argv: *const *const u8,
    sigpipe: u8
) -> Result<isize, !> {
    use crate::{ mem, panic };
    let rt_abort = move |e| {
        mem::forget(e);
        rtabort!("initialization or cleanup bug");
    };

    // 初始化参数、栈等信息，并捕获可能的异常信息，展开异常的栈调用路径
    panic::catch_unwind(move || unsafe { init(argc, argv, sigpipe) }).map_err(rt_abort)?;
    // 调用用户定义的 main 函数
    // 这里会尝试获取用户返回的 exitcode，通过 Termination::report
    let ret_code = panic
        ::catch_unwind(move || panic::catch_unwind(main).unwrap_or(101) as isize)
        .map_err(move |e| {
            mem::forget(e);
            rtabort!("drop of the panic payload panicked");
        });
    // 执行清理程序
    panic::catch_unwind(cleanup).map_err(rt_abort)?;
    // 退出主线程
    panic::catch_unwind(|| crate::sys::exit_guard::unique_thread_exit()).map_err(rt_abort)?;
    ret_code
}
```

让我们一步步分析 `lang_start` 函数：

1. 在 `lang_start` 中我们可以看到这个函数被标记了 `#[lang = "start"]` 这表明是语言的入口函数。
2. `lang_start` 本质是调用的 `lang_start_internal` ，在 `lang_start_internal` 中对资源进行初始化、执行 main、清理资源。
3. 我们可以看到 `lang_start` 函数的参数有一个 `main`，而 `main` 的类型是一个函数，类型声明为 `fn() → T`，T 的约束是 `T: crate::process::Termination + 'static` ，对于我们这次分析来说，最重要的是 `trait Termination` 。

    Termination 相关签名（删除了一些属性宏，不影响理解）：

    ```rust
    #[derive(PartialEq, Eq, Clone, Copy)]
    pub struct ExitCode(u8);

    impl ExitCode {
        pub const SUCCESS: ExitCode = ExitCode(EXIT_SUCCESS as _);
        pub const FAILURE: ExitCode = ExitCode(EXIT_FAILURE as _);

        #[inline]
        pub fn as_i32(&self) -> i32 {
            self.0 as i32
        }
    }

    impl From<u8> for ExitCode {
        fn from(code: u8) -> Self {
            Self(code)
        }
    }

    pub trait Termination {
        /// Is called to get the representation of the value as status code.
        /// This status code is returned to the operating system.
        #[stable(feature = "termination_trait_lib", since = "1.61.0")]
        fn report(self) -> ExitCode;
    }
    ```


现在我们的疑问有了答案，是因为 `Result` 枚举实现了 `Termination`，所以用户定义的 main 函数可以返回 Result 枚举：

```rust
#[stable(feature = "termination_trait_lib", since = "1.61.0")]
impl<T: Termination, E: fmt::Debug> Termination for Result<T, E> {
    fn report(self) -> ExitCode {
        match self {
            Ok(val) => val.report(),
            Err(err) => {
                io::attempt_print_to_stderr(format_args_nl!("Error: {err:?}"));
                ExitCode::FAILURE
            }
        }
    }
}
```

- 通过代码 `crate::sys::backtrace::__rust_begin_short_backtrace(main).report().to_i32()` 可以看到，实际调用了 main 返回值的 report 函数，也就是 `Result::report`，这会返回一个 i32 值，用于标识程序是否正常退出。
- `__rust_begin_short_backtrace` 实际就是一个包装函数，用于防止尾部调用优化的。

### 新的问题又出现了

最开始的问题解决了，但是我们又想到了一个新的问题。

既然 rust 的 lang_start 需要一个 `fn → T, T: crate::process::Termination + 'static` 的类型约束，为什么 main 函数什么也不返回也可以呢？

看这个示例：

```rust
fn main() {
    println!("hello world!");
}
```

回答这个问题，我们首先要知道，在 rust 中函数什么也没返回的情况下，其实也是有返回的，只是可以省略不写而已，上面示例的实际脱糖（剥离语法糖）形式为：

```rust
fn main() -> () {
    println!("hello world!");
}
```

即：默认会返回一个`()`，实际类型名字叫做 `unit` ，中文一般称作单元类型。

恰好，unit 类型，也实现了 Termination trai，所以 main 函数什么也不返回也是可以的。

```rust
#[stable(feature = "termination_trait_lib", since = "1.61.0")]
impl Termination for () {
    #[inline]
    fn report(self) -> ExitCode {
        ExitCode::SUCCESS
    }
}
```

并且 `Termination::report` 签名要求返回一个 `ExitCode`，而 `ExitCode` 又实现了 `From<u8>`，所以实际上还可以在 `main` 函数中返回一个 `u8` 的数字。

例如：

```rust
use std::process::ExitCode;

fn main() -> ExitCode {
    println!("hello world!");
    0.into() // program success
}
```

还可以自定义返回类型，只要实现了 Termination 即可，下面是一个示例：

```rust
use std::process::{ExitCode, Termination};

struct MyExit {
    msg: String,
}

impl MyExit {
    fn new(msg: String) -> Self {
        MyExit { msg }
    }
}

impl Termination for MyExit {
    fn report(self) -> ExitCode {
        if self.msg.eq("ok".into()) {
            0.into()
        } else {
            1.into()
        }
    }
}

fn main() -> MyExit {
    let exit = MyExit::new("ok".into());
    exit
}
```

### 补充资料

1. rust 的 lang_start 也是被调用者，是调用的它呢？在 rust 中有一个 `create_entry_fn` 负责创建 entry 函数，这个函数中会调用 lang_start 函数。[源码](https://github.com/rust-lang/rust/blob/38030ffb4e735b26260848b744c0910a5641e1db/compiler/rustc_codegen_ssa/src/base.rs#L382-L454)。
2. 在裸机开发中（no_std），通常 main 函数是不会返回的，所以是没有 exitcode 的。
