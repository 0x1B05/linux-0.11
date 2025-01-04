#import "../template.typ":*
= 通过fork看系统调用

回到主流程：
#figure(
```c
void main(void) {
    ...    
    move_to_user_mode();
    if (!fork()) {
        init();
    }
    for(;;) pause();
}
```,
caption: [main - fork]
)

#figure(
```c
static _inline _syscall0(int,fork)

#define _syscall0(type,name) \
type name(void) \
{ \
long __res; \
__asm__ volatile ("int $0x80" \
    : "=a" (__res) \
    : "0" (__NR_##name)); \
if (__res >= 0) \
    return (type) __res; \
errno = -__res; \
return -1; \
}
```,
caption: [fork]
)

把所有宏定义展开

#figure(
```c
#define _syscall0(type,name) \
type name(void) \
{ \
    volatile long __res; \
    _asm { \
        _asm mov eax,__NR_##name \
        _asm int 80h \
        _asm mov __res,eax \
    } \
    if (__res >= 0) \
        return (type) __res; \
    errno = -__res; \
    return -1; \
}
```,
caption: [fork - 宏定义展开]
)

相当于定义了一个函数:
#figure(
```c
int fork(void) {
     volatile long __res;
    _asm {
        _asm mov eax,__NR_fork
        _asm int 80h
        _asm mov __res,eax
    }
    if (__res >= 0)
        return (void) __res;
    errno = -__res;
    return -1;
}
```,
caption: [fork - 函数]
)

关键指令就是一个 `0x80` 号软中断的触发，`int 80h`。其中还有一个 `eax` 寄存器里的参数是 `__NR_fork`，这也是个宏定义，值是 `2`。

#tip("Tip")[
    `0x80`中断是在`sched_init` 里面设置的`set_system_gate(0x80, &system_call);`
]

看这个 `system_call` 的汇编代码，我们发现这么一行。

#figure(
```c
_system_call:
    ...
    call [_sys_call_table + eax*4]
    ...
```,
caption: [system_call]
)

刚刚那个值就用上了，`eax` 寄存器里的值是 `2`，所以这个就是在这个 `sys_call_table` 表里找下标 `2` 位置处的函数，然后跳转过去。

接着看 `sys_call_table`
#figure(
```c
fn_ptr sys_call_table[] = { sys_setup, sys_exit, sys_fork, sys_read,
  sys_write, sys_open, sys_close, sys_waitpid, sys_creat, sys_link,
  sys_unlink, sys_execve, sys_chdir, sys_time, sys_mknod, sys_chmod,
  sys_chown, sys_break, sys_stat, sys_lseek, sys_getpid, sys_mount,
  sys_umount, sys_setuid, sys_getuid, sys_stime, sys_ptrace, sys_alarm,
  sys_fstat, sys_pause, sys_utime, sys_stty, sys_gtty, sys_access,
  sys_nice, sys_ftime, sys_sync, sys_kill, sys_rename, sys_mkdir,
  sys_rmdir, sys_dup, sys_pipe, sys_times, sys_prof, sys_brk, sys_setgid,
  sys_getgid, sys_signal, sys_geteuid, sys_getegid, sys_acct, sys_phys,
  sys_lock, sys_ioctl, sys_fcntl, sys_mpx, sys_setpgid, sys_ulimit,
  sys_uname, sys_umask, sys_chroot, sys_ustat, sys_dup2, sys_getppid,
  sys_getpgrp, sys_setsid, sys_sigaction, sys_sgetmask, sys_ssetmask,
  sys_setreuid, sys_setregid
};
```,
caption: [sys_call_table]
)

就是各种函数指针组成的一个数组，就是个系统调用函数表。下标 `2` 位置处就是 `sys_fork` 函数！

通过系统调用这个中断，最终走到内核层面的函数是什么，就是 `sys_fork`。

#figure(
```asm
_sys_fork:
    call _find_empty_process
    testl %eax,%eax
    js 1f
    push %gs
    pushl %esi
    pushl %edi
    pushl %ebp
    pushl %eax
    call _copy_process
    addl $20,%esp
1:  ret
```,
caption: [sys_fork]
)

#figure(caption: [])[#image("images/chapter25-1.png", width: 70%)]

== `execve` -> `syscall3`
定义 `fork` 的系统调用模板函数时，用的是 `syscall0`，这个表示参数个数为 `0`，也就是 `sys_fork` 函数并不需要任何参数。在 `unistd.h` 头文件里，还定义了 `syscall0` ~ `syscall3` 一共四个宏。

```c
#define _syscall0(type,name)
#define _syscall1(type,name,atype,a)
#define _syscall2(type,name,atype,a,btype,b)
#define _syscall3(type,name,atype,a,btype,b,ctype,c)
```

这些参数放在哪里？总得有个约定的地方吧？

以`execve`为例，是一个通常和 `fork` 在一起配合的变身函数，在之后的进程 1 创建进程 2 的过程中，就是这样玩的。
#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        ...
        execve("/bin/sh",argv_rc,envp_rc);
        ...
    }
}
```,
caption: [`fork` + `execve`]
)

#figure(
```c
execve("/bin/sh",argv_rc,envp_rc);

_syscall3(int,execve,const char *,file,char **,argv,char **,envp)

#define _syscall3(type,name,atype,a,btype,b,ctype,c) \
type name(atype a,btype b,ctype c) { \
    volatile long __res; \
    _asm { \
        _asm mov eax,__NR_##name \
        _asm mov ebx,a \
        _asm mov ecx,b \
        _asm mov edx,c \
        _asm int 80h \
        _asm mov __res,eax\
    } \
    if (__res >= 0) \
        return (type) __res; \
    errno = -__res; \
    return -1; \
}
```,
caption: [syscall3]
)

参数 `a` 被放在了 `ebx` 寄存器，参数 `b` 被放在了 `ecx` 寄存器，参数 `c` 被放在了 `edx` 寄存器。

再看看`system_call`的全貌。
#figure(
```asm
_system_call:
    cmpl $nr_system_calls-1,%eax
    ja bad_sys_call
    push %ds
    push %es
    push %fs
    pushl %edx
    pushl %ecx      # push %ebx,%ecx,%edx as parameters
    pushl %ebx      # to the system call
    movl $0x10,%edx     # set up ds,es to kernel space
    mov %dx,%ds
    mov %dx,%es
    movl $0x17,%edx     # fs points to local data space
    mov %dx,%fs
    call _sys_call_table(,%eax,4)
    pushl %eax
    movl _current,%eax
    cmpl $0,state(%eax)     # state
    jne reschedule
    cmpl $0,counter(%eax)       # counter
    je reschedule
ret_from_sys_call:
    movl _current,%eax      # task[0] cannot have signals
    cmpl _task,%eax
    je 3f
    cmpw $0x0f,CS(%esp)     # was old code segment supervisor ?
    jne 3f
    cmpw $0x17,OLDSS(%esp)      # was stack segment = 0x17 ?
    jne 3f
    movl signal(%eax),%ebx
    movl blocked(%eax),%ecx
    notl %ecx
    andl %ebx,%ecx
    bsfl %ecx,%ecx
    je 3f
    btrl %ecx,%ebx
    movl %ebx,signal(%eax)
    incl %ecx
    pushl %ecx
    call _do_signal
    popl %eax
3:  popl %eax
    popl %ebx
    popl %ecx
    popl %edx
    pop %fs
    pop %es
    pop %ds
    iret
```,
caption: [system_call]
)

我们只关注压栈的情况，因为 `system_call` 是通过 `int 80h` 这个软中断进来的，所以也属于中断的一种，具体说是属于特权级发生变化的，且没有错误码情况的中断，所以在这之前栈已经被压了 `SS`、`ESP`、`EFLAGS`、`CS`、`EIP` 这些值。

#figure(caption: [])[#image("images/chapter25-2.png", width: 50%)]
接下来 `system_call` 又压入了一些值，具体说来有 `ds`、`es`、`fs`、`edx`、`ecx`、`ebx`、`eax`。

`system_call.s` 上面的注释，Linus 已经很贴心地写出了此时的堆栈状态。
#figure(
```c
/*
 * Stack layout in 'ret_from_system_call':
 *
 *   0(%esp) - %eax
 *   4(%esp) - %ebx
 *   8(%esp) - %ecx
 *   C(%esp) - %edx
 *  10(%esp) - %fs
 *  14(%esp) - %es
 *  18(%esp) - %ds
 *  1C(%esp) - %eip
 *  20(%esp) - %cs
 *  24(%esp) - %eflags
 *  28(%esp) - %oldesp
 *  2C(%esp) - %oldss
 */
```,
caption: [Linus - comment]
)
就是 CPU 中断压入的 5 个值，加上 `system_call` 手动压入的 7 个值。中断处理程序如果有需要的话，就可以从这里取出它想要的值，包括 CPU 压入的那五个值，或者 `system_call` 手动压入的 7 个值。

比如 `sys_execve` 这个中断处理函数，一开始就取走了位于栈顶 `0x1C` 位置处的 `EIP` 的值。

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

随后在 `do_execve` 函数中，又通过 C 语言函数调用的约定，取走了 `filename`，`argv`，`envp` 等参数。

#figure(
```c
int do_execve(
        unsigned long * eip,
        long tmp,
        char * filename,
        char ** argv,
        char ** envp) {
    ...
}
```,
caption: [do_execve]
)
#pagebreak()
