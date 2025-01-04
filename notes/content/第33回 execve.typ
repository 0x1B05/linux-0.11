#import "../template.typ":*

= execve

先打开 `execve`，开一下它的调用链。
#figure(
```c
static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

// 调用方
execve("/bin/sh",argv_rc,envp_rc);

// 宏定义
_syscall3(int,execve,const char *,file,char **,argv,char **,envp)

// 通过系统调用进入到这里
EIP = 0x1C
_sys_execve:
    lea EIP(%esp),%eax
    pushl %eax
    call _do_execve
    addl $4,%esp
    ret

// 最终执行的函数
int do_execve(
        unsigned long * eip,
        long tmp,
        char * filename,
        char ** argv,
        char ** envp) {
    ...
}
```,
caption: [execve 的调用链]
)

入参：
- `eip` 调用方触发系统调用时由 CPU 压入栈空间中的 `eip` 的指针 。
- `tmp` 是一个无用的占位参数。
- `filename` 是 `"/bin/sh"`
- `argv` 是 `{ "/bin/sh", NULL }`
- `envp` 是 `{ "HOME=/", NULL }`

#figure(
```c
int do_execve(...) {
    // 检查文件类型和权限等
    ...
    // 读取文件的第一块数据到缓冲区
    ...
    // 如果是脚本文件，走这里
    if (脚本文件判断逻辑) {
        ...
    }
    // 如果是可执行文件，走这里
    // 一堆校验可执行文件是否能执行的判断
    ...
    // 进程管理结构的调整
    ...
    // 释放进程占有的页面
    ...
    // 调整线性地址空间、参数列表、堆栈地址等
    ...
    // 设置 eip 和 esp，这里是 execve 变身大法的关键！
    eip[0] = ex.a_entry;
    eip[3] = p;
    return 0;
    ...
}
```,
caption: [do_execve 结构]
)

1. 检查文件类型和权限等
2. 读取文件的第一块数据到缓冲区
3. 脚本文件与可执行文件的判断
4. 校验可执行文件是否能执行
5. 进程管理结构的调整
6. 释放进程占有的页面
7. 调整线性地址空间、参数列表、堆栈地址等
8. 设置 `eip` 和 `esp`，完成摇身一变

核心逻辑就是*加载文件、调整内存、开始执行*

== 读取文件开头 1KB 的数据

#figure(
```c
先是根据文件名，找到并读取文件里的内容

// exec.c
int do_execve(...) {
    ...
    // 根据文件名 /bin/sh 获取 inode
    struct m_inode * inode = namei(filename);
    // 根据 inode 读取文件第一块数据（1024KB）
    struct buffer_head * bh = bread(inode->i_dev,inode->i_zone[0]);
    ...
}
```,
caption: [do_execve - part1]
)

代码里 `inode -> i_zone[0]` 就刚好是文件开头的 1KB 数据。现在这 1KB 的数据，就已经在内存中了，但还没有解析。

== 解析这 1KB 的数据为 `exec` 结构

接下来的工作就是解析它，本质上就是按照指定的数据结构来解读罢了。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    struct exec ex = *((struct exec *) bh->b_data);
    ...
}
```,
caption: [do_execve - exec]
)

先从刚刚读取文件返回的缓冲头指针中取出数据部分 `bh -> data`，也就是文件前 1024 个字节，此时还是一段读不懂的二进制数据。然后按照 `exec` 这个结构体对其进行解析，它便有了生命。

#figure(
```c
struct exec {
    // 魔数
    unsigned long a_magic;
    // 代码区长度
    unsigned a_text;
    // 数据区长度
    unsigned a_data;
    // 未初始化数据区长度
    unsigned a_bss;
    // 符号表长度
    unsigned a_syms;
    // 执行开始地址
    unsigned a_entry;
    // 代码重定位信息长度
    unsigned a_trsize;
    // 数据重定位信息长度
    unsigned a_drsize;
};
```,
caption: [struct exec]
)

上面的代码就是 `exec` 结构体，这是 `a.out` 格式文件的头部结构，现在的 Linux 已经弃用了这种古老的格式，改用 ELF 格式了，但大体的思想是一致的。

== 判断是脚本文件还是可执行文件
 Linux 脚本文件前面有这么一坨。

#figure(
```sh
#!/bin/sh
#!/usr/bin/python
```,
caption: [shebang]
)

我们通常可以直接执行这样的文件，原因就在下面这个代码里。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    if ((bh->b_data[0] == '#') && (bh->b_data[1] == '!') {
        ...
    }
    brelse(bh);
    ...
}
```,
caption: [brelse]
)

判断前面两个字符是不是 `#!`，是就走脚本文件的执行逻辑。

现在的 `/bin/sh` 是个可执行的二进制文件，所以直接看外面，执行可执行二进制文件的逻辑。

第一步就是 `brelse` 释放这个缓冲块，因为已经把这个缓冲块内容解析成 `exec` 结构保存到我们程序的栈空间里了，那么这个缓冲块就可以释放，用于其他读取磁盘时的缓冲区。

== 准备参数空间

执行 `/bin/sh` 时，还传了 `argc` 和 `envp` 参数，就是下面这代码实现的。

#figure(
```c
#define PAGE_SIZE 4096
#define MAX_ARG_PAGES 32

// exec.c
int do_execve(...) {
    ...
    // p = 0x1FFFC = 128K - 4
    unsigned long p = PAGE_SIZE * MAX_ARG_PAGES - 4;
    ...
    // p = 0x1FFF5 = 128K - 4 - 7
    p = copy_strings(envc,envp,page,p,0);
    // p = 0x1FFED = 128K - 4 - 7 - 8
    p = copy_strings(argc,argv,page,p,0);
    ...
    // p = 0x3FFFFED = 64M - 4 - 7 - 8
    p += change_ldt(ex.a_text,page)-MAX_ARG_PAGES*PAGE_SIZE;
    // p = 0x3FFFFD0
    p = (unsigned long) create_tables((char *)p,argc,envc);
    ...
    // 设置栈指针
    eip[3] = p;
}
```,
caption: [do_execve - 参数]
)

准备参数空间的过程，同时也伴随着一个表示地址的 `unsigned long p` 的计算轨迹。

开头一行计算出的 p 值为 `p = 4096 * 32 - 4 = 0x20000 - 4 = 128K - 4`。这表示参数表，每个进程的参数表大小为 128K，就表示每个进程的线性地址空间的末端 128K，是为参数表保留的，目前这个 p 就指向了参数表的开始处（偏移 4 字节）。

#figure(caption: [])[#image("images/chapter33-1.png", width: 60%)]

接下来两个 `copy_strings` 就是往这个参数表里面存放信息，不过具体存放的只是字符串常量值的信息，随后他们将被引用，有点像 Java 里 class 文件的字符串常量池思想。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    // p = 0x1FFF5 = 128K - 4 - 7
    p = copy_strings(envc,envp,page,p,0);
    // p = 0x1FFED = 128K - 4 - 7 - 8
    p = copy_strings(argc,argv,page,p,0);
    ...
}
```,
caption: [do_execve - copy_strings]
)

具体说来，`envp` 表示字符串参数 `"HOME=/"`，`argv` 表示字符串参数 `"/bin/sh"`，两个 copy 就表示把这个字符串参数往参数表里存，相应地指针 `p` 也往下移动（共移动了 7 + 8 = 15 个字节），和压栈的效果是一样的。

#figure(caption: [])[#image("images/chapter33-2.png", width: 60%)]

实际上这些字符串都是紧挨着的，通过 debug 查看参数表位置处的内存便可以看到真正存放的方式。

#figure(caption: [])[#image("images/chapter33-3.png", width: 70%)]

两个字符串被安排在了参数表内存处，且参数与参数之间用 `00` 也就是 `NULL` 来分隔。

接下来是更新局部描述符。

#figure(
```c
#define PAGE_SIZE 4096
#define MAX_ARG_PAGES 32

// exec.c
int do_execve(...) {
    ...
    // p = 0x3FFFFED = 64M - 4 - 7 - 8
    p += change_ldt(ex.a_text,page)-MAX_ARG_PAGES*PAGE_SIZE;
    ...
}
```,
caption: [do_execve - change_ldt]
)

就是根据 `ex.a_text` 修改局部描述符中的代码段限长 `code_limit`。`ex` 结构里的 `a_text` 是生成 `/bin/sh` 这个 `a.out` 格式的文件时，写在头部的值，用来表示代码段的长度。至于具体是怎么生成的，无需关心。

由于这个函数返回值是数据段限长，也就是 64M，所以最终的 `p` 值被调整为了以每个进程的线性地址空间视角下的地址偏移。

#figure(caption: [])[#image("images/chapter33-4.png", width: 60%)]

接下来就是真正构造参数表的环节了。

#figure(
```c
#define PAGE_SIZE 4096
#define MAX_ARG_PAGES 32

// exec.c
int do_execve(...) {
    ...
    // p = 0x3FFFFD0
    p = (unsigned long) create_tables((char *)p,argc,envc);
    ...
}
```,
caption: [do_execve - create_tables]
)

刚刚仅仅是往参数表里面丢入了需要的字符串常量值信息，现在就需要真正把参数表构建起来。

展开 `create_tables`。

#figure(
```c
/*
 * create_tables() parses the env- and arg-strings in new user
 * memory and creates the pointer tables from them, and puts their
 * addresses on the "stack", returning the new stack pointer value.
 */
static unsigned long * create_tables(char * p,int argc,int envc) {
    unsigned long *argv,*envp;
    unsigned long * sp;

    sp = (unsigned long *) (0xfffffffc & (unsigned long) p);
    sp -= envc+1;
    envp = sp;
    sp -= argc+1;
    argv = sp;
    put_fs_long((unsigned long)envp,--sp);
    put_fs_long((unsigned long)argv,--sp);
    put_fs_long((unsigned long)argc,--sp);
    while (argc-->0) {
        put_fs_long((unsigned long) p,argv++);
        while (get_fs_byte(p++)) /* nothing */ ;
    }
    put_fs_long(0,argv);
    while (envc-->0) {
        put_fs_long((unsigned long) p,envp++);
        while (get_fs_byte(p++)) /* nothing */ ;
    }
    put_fs_long(0,envp);
    return sp;
}
```,
caption: [create_tables]
)

一行一行仔细分析，不难分析出参数表空间。

#figure(caption: [])[#image("images/chapter33-5.png", width: 30%)]

最后，将 `sp` 返回给 `p`，这个 `p` 将作为一个新的栈顶指针，给即将要完成替换的 `/bin/sh` 程序，也就是下面的代码。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    // 设置栈指针
    eip[3] = p;
}
```,
caption: [do_execve - 设置栈指针]
)

为什么这样操作就可以达到更换栈顶指针的作用呢？那我们结合着更换代码指针 PC 来进行讲解。

== 设置 `eip` 和 `esp`

下面这两行就是 `execve` 的关键，解释了为什么能变成一个新程序开始执行。

#figure(
```c
// exec.c
int do_execve(unsigned long * eip, ...) {
    ...
    eip[0] = ex.a_entry;
    eip[3] = p; 
    ...
}
```,
caption: [设置eip和esp]
)

一个新程序开始执行，本质上就是，代码指针 `eip` 和栈指针 `esp` 指向了一个新的地方。

代码指针 `eip` 决定了 CPU 将执行哪一段指令，栈指针 `esp` 决定了 CPU 压栈操作的位置，以及读取栈空间数据的位置，在高级语言视角下就是局部变量以及函数调用链的栈帧。

所以这两行代码，第一行重新设置了代码指针 `eip` 的值，指向 `/bin/sh` 这个 `a.out` 格式文件的头结构 `exec` 中的 `a_entry` 字段，表示该程序的入口地址。

第二行重新设置了栈指针 `esp` 的值，指向了我们经过一路计算得到的 `p`，也就是图中 `sp` 的值。将这个值作为新的栈顶。

== 计算机的世界没有魔法

至于为什么往 `eip` 的 `0` 和 `3` 索引位置处写入数据，就可以达到替换 `eip` 和 `esp` 的目的，那就得看看这个 `eip` 变量是怎么来的了。

#figure(
```c
static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

// 调用方
execve("/bin/sh",argv_rc,envp_rc);

// 宏定义
_syscall3(int,execve,const char *,file,char **,argv,char **,envp)

// 通过系统调用进入到这里
EIP = 0x1C
_sys_execve:
    lea EIP(%esp),%eax
    pushl %eax
    call _do_execve
    addl $4,%esp
    ret

// exec.c
int do_execve(unsigned long * eip, ...) {
    ...
    eip[0] = ex.a_entry;
    eip[3] = p; 
    ...
}
```,
caption: [execve 调用链]
)

`do_execve` 函数，是通过一开始的 `execve` 函数触发了系统调用来到的这里。系统调用是一种中断，前面说过，中断时 CPU 会给栈空间里压入一定的信息，这部分信息是死的，查手册可以查得到。

#figure(caption: [])[#image("images/chapter33-6.png", width: 60%)]

然后，进入中断以后，通过系统调用查表进入到 `_sys_execve` 这里。

#figure(
```asm
EIP = 0x1C
_sys_execve:
    lea EIP(%esp),%eax
    pushl %eax
    call _do_execve
    addl $4,%esp
    ret
```,
caption: [sys_execve]
)

在真正调用 `do_execve` 函数时，`_sys_execve` 这段代码插入了一个小步骤，就是把当前栈顶指针 `esp` 偏移到 `EIP` 处的地址值给当做第一个参数 `unsigned long * eip` 传入进来了。

而偏移 `EIP` 处的位置，恰好就是中断时压入的 `EIP` 的值的位置，表示中断发生前的指令寄存器的值。所以 `eip[0]` 就表示栈空间里的 `EIP` 位置，`eip[3]` 就表示栈空间里的 `ESP` 位置。

#figure(caption: [])[#image("images/chapter33-7.png", width: 60%)]

由于现在处于中断，所以中断返回后，也就是 `do_execve` 这个函数 `return` 之后，就会寻找中断返回前的这几个值（包括 `eip` 和 `esp`）进行恢复。所以如果把这个栈空间里的 `eip` 和 `esp` 进行替换，换成执行 `/bin/sh` 所需要的 `eip` 和 `esp`，那么中断返回的"恢复"工作，就犹如"跳转"到一个新程序那里一样，其实是我们欺骗了 CPU，达到了 `execve` 这个函数的魔法效果。

#pagebreak()
