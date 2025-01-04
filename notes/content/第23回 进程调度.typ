#import "../template.typ":*

= 进程调度

假如有三段代码被加载到内存中。
#figure(caption: [])[#image("images/chapter23-1.png", width: 40%)]

== 整体流程设计

如何做到，一会去程序1运行，一会去程序2运行？

第一种办法就是，程序 1 的代码里，每隔几行就写一段代码，主动放弃自己的执行权，跳转到程序 2 的地方运行。然后程序 2 也是如此。但这种依靠程序自己的办法肯定不靠谱。
 
所以第二种办法就是，由一个不受任何程序控制的，第三方的不可抗力，每隔一段时间就中断一下 CPU 的运行，然后跳转到一个特殊的程序那里，这个程序通过某种方式获取到 CPU 下一个要运行的程序的地址，然后跳转过去。这个每隔一段时间就中断 CPU 的不可抗力，就是由定时器触发的时钟中断。

总得有一个结构来记录各个进程的信息，比如它上一次执行到哪里了。不妨假设这个结构叫 `tast_struct`。

#figure(
```c
struct task_struct {
    ?
}
```,
caption: [task_struct - ?]
)

== 上下文环境

每个程序最终的本质就是执行指令。这个过程会涉及*寄存器，内存和外设端口*。

内存还有可能设计成相互错开的，互不干扰，比如进程 1 用 0~1K 的内存空间，进程 2 用 1K~2K 的内存空间。不过寄存器一共就那么点，肯定做不到互不干扰，可能一个进程就把寄存器全用上了。(程序 1 刚刚往 `eax` 写入一个值，准备用，这时切换到进程 2 了，又往 `eax` 里写入了一个值。那么之后再切回进程 1 的时候，🐔。)
#figure(caption: [])[#image("images/chapter23-2.png", width: 60%)]

稳妥的做法就是，每次切换进程时，都把当前这些寄存器的值存到一个地方，以便之后切换回来的时候恢复。每个进程的结构 `task_struct` 里面，有一个叫 `tss` 的结构，存储的就是 CPU 这些寄存器的信息。

#figure(
```c
struct task_struct {
    ...
    struct tss_struct tss;
}

struct tss_struct {
    long    back_link;  /* 16 high bits zero */
    long    esp0;
    long    ss0;        /* 16 high bits zero */
    long    esp1;
    long    ss1;        /* 16 high bits zero */
    long    esp2;
    long    ss2;        /* 16 high bits zero */
    long    cr3;
    long    eip;
    long    eflags;
    long    eax,ecx,edx,ebx;
    long    esp;
    long    ebp;
    long    esi;
    long    edi;
    long    es;     /* 16 high bits zero */
    long    cs;     /* 16 high bits zero */
    long    ss;     /* 16 high bits zero */
    long    ds;     /* 16 high bits zero */
    long    fs;     /* 16 high bits zero */
    long    gs;     /* 16 high bits zero */
    long    ldt;        /* 16 high bits zero */
    long    trace_bitmap;   /* bits: trace 0, bitmap 16-31 */
    struct i387_struct i387;
};
```,
caption: [task_struct - tss_struct]
)

tss 结构里有个 `cr3`, 表示 `cr3` 寄存器里存的值，而 `cr3` 寄存器是指向页目录表首地址的。
#figure(caption: [])[#image("images/chapter23-3.png", width: 60%)]

那么指向不同的页目录表，整个页表结构就是完全不同的一套，那么线性地址到物理地址的映射关系就有能力做到不同。有了这个 `cr3` 字段，只要建立不同的映射关系，由操作系统来建立不同的页目录表并替换 `cr3` 寄存器。

这也可以理解为，保存了*内存映射的上下文信息*。

#tip("Tip")[
Linux 0.11 并不是通过替换 `cr3` 寄存器来实现内存互不干扰的，它的实现更为简单，这是后话了。
]

== 运行时间信息

如何判断一个进程该让出 CPU 了，切换到下一个进程呢？
- 每次时钟中断时都切换一次: 一不灵活，二完全依赖时钟中断的频率，危险。
- 给进程一个属性，叫剩余时间片，每次时钟中断来了之后都 `-1`，如果减到 `0` 了，就触发切换进程的操作。

在 Linux 0.11 里，这个属性就是 counter。

#figure(
```c
struct task_struct {
    ...
    long counter;
    ...
    struct tss_struct tss;
}
void do_timer(long cpl) {
    ...
    // 当前线程还有剩余时间片，直接返回
    if ((--current->counter)>0) return;
    // 若没有剩余时间片，调度
    schedule();
}
```,
caption: [task_struct - counter]
)
用法就是每次中断都判断一下是否到 `0` 了。如果还没到 `0`，就直接返回，相当于这次时钟中断什么也没做，仅仅是给当前进程的时间片属性做了 `-1` 操作。如果已经到 `0` 了，就触发进程调度，选择下一个进程并使 CPU 跳转到那里运行。

== 优先级

`counter` 一开始的时候该是多少呢？随着 `counter` 不断递减，减到 `0` 时，下一轮回中这个 `counter` 应该赋予什么值呢？
 
就是 counter 的初始化问题，需要有一个属性来记录这个值。
 
往宏观想一下，这个值越大，那么 `counter` 就越大，那么每次轮到这个进程时，它在 CPU 中运行的时间就越长，也就是这个进程比其他进程得到了更多 CPU 运行的时间。那我们可以把这个值称为优先级。

#figure(
```c
struct task_struct {
    ...
    long counter;
    long priority;
    ...
    struct tss_struct tss;
}
```,
caption: [task_struct - priority]
)

每次一个进程初始化时，都把 `counter` 赋值为这个 `priority`，而且当 `counter` 减为 `0` 时，下一次分配时间片，也赋值为这个。
 
== 进程状态

有了上面那三个信息，就已经可以完成进程的调度了。如果操作系统让所有进程都得到同样的运行时间，连 `counter` 和 `priority` 都不用，就定一个固定值一直递减，减到 `0` 了就随机切一个新进程。这样就仅仅维护好寄存器的上下文信息 `tss` 就好了。
 
但总要不断优化以适应不同场景的用户需求的，那我们再优化一个细节。
 
一个进程中有一个读取硬盘的操作，发起读请求后，要等好久才能得到硬盘的中断信号。这个时间该进程再占用着 CPU 也没用，此时可以选择主动放弃 CPU ，然后再把自己的状态标记为等待中。意思是告诉进程调度的代码，"先别调度我，因为我还在等硬盘的中断，现在轮到我了也没用，把机会给别人吧。"
 
那这个状态可以记录一个属性了，叫 `state`，记录了此时进程的状态。

#figure(
```c
#define TASK_RUNNING          0
#define TASK_INTERRUPTIBLE    1
#define TASK_UNINTERRUPTIBLE  2
#define TASK_ZOMBIE           3
#define TASK_STOPPED          4

struct task_struct {
    long state;
    long counter;
    long priority;
    ...
    struct tss_struct tss;
}
```,
caption: [task - state]
)
#pagebreak()
