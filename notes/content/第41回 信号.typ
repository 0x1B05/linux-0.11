#import "../template.typ":*

= 信号

如果程序正在被 shell 程序执行时，按下了键盘中的 `CTRL+C`，程序就被迫终止，并再次返回到了 shell 等待用户输入命令的状态。

#figure(
```c
[root@linux0.11] cat info.txt | wc -l
...(这里假设程序要执行很长时间，此时按下ctrl+c)
^C
[root@linux0.11]
```,
caption: [Ctrl^C]
)

按下 CTRL+C 时。根据先前所讲，键盘中断处理函数自然会走到处理字符的 `copy_to_cooked` 函数里。

#figure(
```c
#define INTMASK (1<<(SIGINT-1))
// kernel/chr_drv/tty_io.c
void copy_to_cooked (struct tty_struct *tty) {
    ...
    if (c == INTR_CHAR (tty)) {
        tty_intr (tty, INTMASK);
        continue;
    }
    ...
}
```,
caption: [copy_to_cooked - INTR_CHAR]
)

就是当 `INTR_CHAR` 发现字符为中断字符时（其实就是 `CTRL+C`），就调用 `tty_intr` 给进程发送信号。

`tty_intr` 函数很简单，就是给所有组号等于 `tty` 组号的进程，发送信号。

#figure(
```c
// kernel/chr_drv/tty_io.c
void tty_intr (struct tty_struct *tty, int mask) {
    int i;
    ...
    for (i = 0; i < NR_TASKS; i++) {
        if (task[i] && task[i]->pgrp == tty->pgrp) {
            task[i]->signal |= mask;
        }
    }
}
```,
caption: [tty_intr]
)

发送信号就是给进程 `task_struct` 结构中的 `signal` 的相应位置 1 而已。从上面的宏定义中也可以看出，发送的是 `SIGINT` 信号。

`SIGINT` 就是个数字。它就定义在 `signal.h` 这个头文件里。

#figure(
```c
// signal.h
#define SIGHUP  1       /* hangup */
#define SIGINT  2       /* interrupt */
#define SIGQUIT 3       /* quit */
#define SIGILL  4       /* illegal instruction (not reset when caught) */
#define SIGTRAP 5       /* trace trap (not reset when caught) */
#define SIGABRT 6       /* abort() */
#define SIGPOLL 7       /* pollable event ([XSR] generated, not supported) */
#define SIGIOT  SIGABRT /* compatibility */
#define SIGEMT  7       /* EMT instruction */
#define SIGFPE  8       /* floating point exception */
#define SIGKILL 9       /* kill (cannot be caught or ignored) */
#define SIGBUS  10      /* bus error */
#define SIGSEGV 11      /* segmentation violation */
#define SIGSYS  12      /* bad argument to system call */
#define SIGPIPE 13      /* write on a pipe with no one to read it */
#define SIGALRM 14      /* alarm clock */
#define SIGTERM 15      /* software termination signal from kill */
#define SIGURG  16      /* urgent condition on IO channel */
#define SIGSTOP 17      /* sendable stop signal not from tty */
#define SIGTSTP 18      /* stop signal from tty */
#define SIGCONT 19      /* continue a stopped process */
#define SIGCHLD 20      /* to parent on child stop or exit */
#define SIGTTIN 21      /* to readers pgrp upon background tty read */
#define SIGTTOU 22      /* like TTIN for output if (tp->t_local&LTOSTOP) */
#define SIGIO   23      /* input/output possible signal */
#define SIGXCPU 24      /* exceeded CPU time limit */
#define SIGXFSZ 25      /* exceeded file size limit */
#define SIGVTALRM 26    /* virtual time alarm */
#define SIGPROF 27      /* profiling time alarm */
#define SIGWINCH 28     /* window size changes */
#define SIGINFO 29      /* information request */
#define SIGUSR1 30      /* user defined signal 1 */
#define SIGUSR2 31      /* user defined signal 2 */
```,
caption: [signal.h]
)

这里把 Linux 0.11 支持的信号都放出来了，有熟悉的按下 `CTRL+C` 时的信号 `SIGINT`，有我们通常杀死进程时 `kill -9` 的信号 `SIGKILL`，还有 core dump 内存访问出错时经常遇到的 `SIGSEGV`。

在现代 Linux 操作系统中，输入个 `kill -l` 便可知道你所在的系统所支持的信号，下面是我在我购买的一台腾讯云主机上的结果。
#figure(caption: [])[#image("images/chapter41-1.png", width: 80%)]

现在这个进程的 `tast_struct` 结构中的 `signal` 就有了对应信号位的值，那么在下次时钟中断到来时，便会通过 `timer_interrupt` 这个时钟中断处理函数，一路调用到 `do_signal` 方法。

#figure(
```c
// kernel/signal.c
void do_signal (long signr ...) {
    ...
    struct sigaction *sa = current->sigaction + signr - 1;
    sa_handler = (unsigned long) sa->sa_handler;
    // 如果信号处理函数为空，则直接退出
    if (!sa_handler) {
        ...
        do_exit (1 << (signr - 1));
        ...
    }
    // 否则就跳转到信号处理函数的地方运行
    *(&eip) = sa_handler;
    ...
}
```,
caption: [do_signal]
)

可以看到，进入 `do_signal` 函数后，如果当前信号 `signr` 对应的信号处理函数 `sa_handler` 为空时，就直接调用 `do_exit` 函数退出，也就是看到的按下 `CTRL+C` 之后退出的样子了。

但是，如果信号处理函数不为空，那么就通过将 `sa_handler` 赋值给 `eip` 寄存器，也就是指令寄存器的方式，跳转到相应信号处理函数处运行。信号处理函数注册在每个进程 `task_struct` 中的 `sigaction` 数组中。

#figure(
```c
// signal.h
struct  sigaction {
    union __sigaction_u __sigaction_u;  /* signal handler */
    sigset_t sa_mask;               /* signal mask to apply */
    int     sa_flags;               /* see signal options below */
};

/* union for signal handlers */
union __sigaction_u {
    void    (*__sa_handler)(int);
    void    (*__sa_sigaction)(int, struct __siginfo *,
        void *);
};

// sched.h
struct task_struct {
    ...
    struct sigaction sigaction[32];
    ...
}
```,
caption: [sigaction]
)

只需要给 `sigaction` 对应位置处填写上信号处理函数即可。那么如何注册这个信号处理函数呢，通过调用 `signal` 这个库函数即可。

我们可以写一个小程序。

#figure(
```c
#include <stdio.h>
#include <signal.h>

void int_handler(int signal_num) {
    printf("signal receive %d\n", signal_num);
}

int main(int argc, char ** argv) {
    signal(SIGINT, int_handler);
    for(;;)
        pause();
    return 0;
}
```,
caption: [signal - demo]
)

这是个死循环的 `main` 函数，只不过，通过 `signal` 注册了 `SIGINT` 的信号处理函数，里面做的事情仅仅是打印一下信号值。编译并运行它，我们会发现在按下 `CTRL+C` 之后程序不再退出，而是输出了我们 `printf` 的话。
#figure(caption: [])[#image("images/chapter41-2.png", width: 50%)]

多次按 CTRL+C，这个程序仍然不会退出，会一直输出上面的话。

#figure(caption: [])[#image("images/chapter41-3.png", width: 40%)]

这就做到了亲手捕获 `SIGINT` 这个信号。但这个程序有点不友好，永远无法 `CTRL+C` 结束了，优化一下代码，让第一次按下 `CTRL+C` 后的信号处理函数，把 `SIGINT` 的处理函数重新置空。

#figure(
```c
#include <stdio.h>
#include <signal.h>

void int_handler(int signal_num) {
    printf("signal receive %d\n", signal_num);
    signal(SIGINT, NULL);
}

int main(int argc, char ** argv) {
    signal(SIGINT, int_handler);
    for(;;)
        pause();
    return 0;
}
```,
caption: [signal - demo2]
)

这次按下第二次 `CTRL+C` 程序就会退出了，这也间接证明了，当没有为 `SIGINT` 注册信号处理函数时，程序接收到 `CTRL+C` 的 `SIGINT` 信号时便会退出。

#pagebreak()
