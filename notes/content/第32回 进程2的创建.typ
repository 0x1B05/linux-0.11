#import "../template.typ":*

= 进程2的创建

进程1的创建结束了，接下来是控制流程和创建新进程。

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        close(0);
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
        _exit(2);
    }
    if (pid>0)
        while (pid != wait(&i))
            /* nothing */;
    while (1) {
        if (!(pid=fork())) {
            close(0);close(1);close(2);
            setsid();
            (void) open("/dev/tty0",O_RDWR,0);
            (void) dup(0);
            (void) dup(0);
            _exit(execve("/bin/sh",argv,envp));
        }
        while (1)
            if (pid == wait(&i))
                break;
        printf("\n\rchild %d died with code %04x\n\r",pid,i);
        sync();
    }
    _exit(0);   /* NOTE! _exit, not exit() */
}
```,
caption: [init - rest]
)

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        close(0);
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
        _exit(2);
    }
    ...
}
```,
caption: [init - part3]
)

先看这个第一段
1. `fork` 一个新的子进程，此时就是进程 2 了。
2. 在进程 2 里关闭（`close`） `0` 号文件描述符。
3. 只读形式打开（`open`） `rc` 文件。
4. 然后执行（`execve`） `sh` 程序。

== `fork`

进程 0 `fork` 出进程 1 就是将进程0的 `task_struct` 结构进行一下复制。再重写一些基本信息，包括元信息和 `tss` 里的寄存器信息。再之后，用 `copy_page_tables` 复制了一下页表（这里涉及到写时复制的伏笔）。

这里的进程 1 fork 出进程 2，也是同样的流程，不同之处在于两点细节：
1. 进程 1 打开了三个文件描述符并指向了 `tty0`，那这个也被复制到进程 2 了，具体说来就是进程结构 `task_struct` 里的 `flip[]` 数组被复制了一份。
  - 而进程 0 `fork` 出进程 1 时是没有复制这部分信息的，因为进程 0 没有打开任何文件。进程 0 没有与外设交互的能力，进程 1 有，其实就是这个 `flip` 数组里有没有东西而已
2. 进程 0 复制进程 1 时页表的复制只有 160 项，也就是映射 640K，而之后进程的复制，统统都是复制 1024 项，也就是映射 4M 空间。
  #figure(
  ```c
  int copy_page_tables(unsigned long from,unsigned long to,long size) {
      ...
      nr = (from==0)?0xA0:1024;
      ...
  }
  ```,
  caption: [copy_page_tables - nr]
  )

#figure(caption: [])[#image("images/chapter32-1.png", width: 60%)]

== `close`


好了，我们继续看。

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        close(0);
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
        _exit(2);
    }
    ...
}
```,
caption: [init - part4]
)

`fork` 完之后，后面 `if` 里面的代码都是进程 2 在执行了。`close(0)` 就是关闭 0 号文件描述符，也就是进程 1 复制过来的打开了 `tty0` 并作为标准输入的文件描述符，那么此时 0 号文件描述符就空出来了。

下面是 close 对应的系统调用函数，很简单。

#figure(
```c
int sys_close(unsigned int fd) {   
    ...
    current->filp[fd] = NULL;
    ...
}
```,
caption: [sys_close]
)


== `open`

接下来 open 函数以只读形式打开了一个叫 `/etc/rc` 的文件，刚好占据了 0 号文件描述符的位置。

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        ...
        open("/etc/rc",O_RDONLY,0);
        ...
    }
    ...
}
```,
caption: [init - open]
)

这个 `rc` 文件表示配置文件，具体什么内容，取决于硬盘里这个位置处放了什么内容，与操作系统内核无关，暂且不用管。

此时，进程 2 与进程 1 几乎完全一样，只不过进程 2 通过 `close` 和 `open` 操作，将原来进程 1 的指向标准输入的 0 号文件描述符，重新指向了 `/etc/rc` 文件。

而这个 `rc` 文件是后面 `sh` 程序要用到的。

== `execve`

execve 函数调用，使进程2摇身一变，成为 `/bin/sh` 程序继续运行！

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        ...
        execve("/bin/sh",argv_rc,envp_rc);
        ...
    }
    ...
}
```,
caption: [init - execve]
)

这里就包含着操作系统究竟是如何加载并执行一个程序的原理，包括如何从文件系统中找到这个文件，如何解析一个可执行文件（在现代的 Linux 里称作 ELF 可执行文件），如何讲可执行文件中的代码和数据加载到内存并运行。

加载到内存并运行又包含着虚拟内存等相关的知识。

#pagebreak()
