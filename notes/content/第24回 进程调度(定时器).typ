#import "../template.typ":*

= 进程调度(定时器)

#figure(
```c
struct task_struct {
    long state;
    long counter;
    long priority;
    ...
    struct tss_struct tss;
}
```,
caption: [task_struct - part]
)

`sched_init` 开启了定时器，定时器每隔一段时间就会向 CPU 发起一个中断信号。这个间隔时间被设置为 10 ms，也就是 100 Hz。发起的中断叫时钟中断，其中断向量号被设置为了 `0x20`。

```c
schedule.c

#define HZ 100
...
set_intr_gate(0x20, &timer_interrupt);
...
```

时钟中断，也就是 `0x20` 号中断来临时，CPU 会查找中断向量表中 `0x20` 处的函数地址，即中断处理函数，并跳转过去执行。这个中断处理函数就是 `timer_interrupt`，是用汇编语言写的。

#figure(
```asm
_timer_interrupt:
    ...
    // 增加系统滴答数
    incl _jiffies
    ...
    // 调用函数 do_timer
    call _do_timer
    ...
```,
caption: [system_call - timer_interrupt]
)

这个函数做了两件事，一个是将系统滴答数这个变量 `jiffies++` ，一个是调用了另一个函数 `do_timer`。

#figure(
```c
void do_timer(long cpl) {
    ...
    // 当前线程还有剩余时间片，直接返回
    if ((--current->counter)>0) return;
    // 若没有剩余时间片，调度
    schedule();
}
```,
caption: [do_timer]
)

`do_timer` 最重要的部分就是上面这段代码， 首先将当先进程的时间片 `-1`，然后判断：
- 如果时间片仍然大于零，则什么都不做直接返回。
- 如果时间片已经为零，则调用 `schedule()`，很明显，这就是进行进程调度的主干。

#figure(
```c
void schedule(void) {
    int i, next, c;
    struct task_struct ** p;
    ...
    while (1) {
        c = -1;
        next = 0;
        i = NR_TASKS;
        p = &task[NR_TASKS];
        while (--i) {
            if (!*--p)
                continue;
            if ((*p)->state == TASK_RUNNING && (*p)->counter > c)
                c = (*p)->counter, next = i;
        }
        if (c) break;
        for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
            if (*p)
                (*p)->counter = ((*p)->counter >> 1) +
                        (*p)->priority;
    }
    switch_to(next);
}
```,
caption: [schedule]
)

做个化简
#figure(
```c
void schedule(void) {
    int next = get_max_counter_and_runnable_thread();
    refresh_all_thread_counter();
    switch_to(next);
}
```,
caption: [schedule]
)

这个函数就做了三件事：
1. 拿到剩余时间片（`counter`的值）最大且在 `runnable` 状态（`state = 0`）的进程号 `next`。
2. 如果所有 `runnable` 进程时间片都为 `0`，则将所有进程（不仅仅是 `runnable` 的进程）的 `counter` 重新赋值（`counter = counter/2 + priority`），然后再次执行步骤 1。
3. 最后拿到了一个进程号 `next`，调用了 `switch_to(next)` 这个方法，就切换到了这个进程去执行了。

看 `switch_to` 方法，是用内联汇编语句写的。是进程切换的最底层的代码了。

#figure(
```asm
#define switch_to(n) {\
struct {long a,b;} __tmp; \
__asm__("cmpl %%ecx,_current\n\t" \
    "je 1f\n\t" \
    "movw %%dx,%1\n\t" \
    "xchgl %%ecx,_current\n\t" \
    "ljmp %0\n\t" \
    "cmpl %%ecx,_last_task_used_math\n\t" \
    "jne 1f\n\t" \
    "clts\n" \
    "1:" \
    ::"m" (*&__tmp.a),"m" (*&__tmp.b), \
    "d" (_TSS(n)),"c" ((long) task[n])); \
}
```,
caption: [sched.h - switch_to]
)

其实主要就干了一件事，就是 `ljmp` 到新进程的 `tss` 段处。CPU 规定，如果 `ljmp` 指令后面跟的是一个 `tss` 段，那么，会由硬件将当前各个寄存器的值保存在当前进程的 `tss` 中，并将新进程的 `tss` 信息加载到各个寄存器。

#figure(caption: [])[#image("images/chapter24-1.png", width: 70%)]

#pagebreak()
