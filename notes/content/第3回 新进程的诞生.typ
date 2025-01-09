#import "../template.typ": *

= 新进程的诞生

== 全局概述

到了第三部分，就是从内核态切换到用户态，然后通过 `fork` 创建出一个新的进程，再之后老进程进入死循环。

#figure(
```c
void main(void) {
    // 第二部分的内容，各种初始化工作
    ...
    // 第三部分的内容，一个新进程的诞生
    move_to_user_mode();
    if (!fork()) {
        // 新进程里干了啥，是第四部分的内容
        init();
    }
    // 死循环，操作系统怠速状态
    for(;;) pause();
}
```,
caption: [main - part3]
)

第一句是 `move_to_user_mode`，就是转变为用户态模式。

一旦转变为了用户态，那么之后的代码将一直处于用户态的模式，除非发生了中断，那么将会从用户态陷入内核态，不过当中断处理程序执行完之后，又会通过中断返回指令从内核态回到用户态。

#figure(caption: [])[#image("images/chapter21-1.png", width: 60%)]

第二句是 `fork`，这是创建一个新进程，而且所有用户进程想要创建新的进程，都需要调用这个函数。

原来操作系统只有一个执行流，就是一直看过来的所有代码，就是进程 0。调用完 `fork` 之后，现在又多了一个进程，叫做进程 1。

更准确的说法是，一路看过来的代码能够被自信地称作进程 0 的确切时刻，是 `sched_init` 里为当前执行流添加了一个进程管理结构到 `task` 数组里，同时开启了定时器以及时钟中断的那一刻。

#figure(caption: [])[#image("images/chapter21-2.png", width: 60%)]

第三句是 `init`，只有进程 1 会走到这个分支来执行。这里的代码很多，本身需要完成如加载根文件系统的任务，同时又会创建出一个新的进程 2，在进程 2 里又会加载与用户交互的 shell 程序，此时操作系统就正式成为了用户可用的一个状态了。

第四句是 `pause`，当没有任何可运行的进程时，操作系统会悬停在这里，达到怠速状态。

== `move_to_user_mode`: 从内核态到用户态

=== 内核态与用户态的本质-特权级

从一个最大的视角来看，这一切都源于 CPU 的保护机制。CPU 为了配合操作系统完成保护机制这一特性，分别设计了分段保护机制与分页保护机制。

#figure(caption: [])[#image("images/chapter22-1.png", width: 80%)]

有关特权级的保护，实际上属于分段保护机制的一种。目前正在执行的代码地址，是通过 CPU 中的两个寄存器 `cs:eip` 指向的，`cs` 寄存器是代码段寄存器，里面存着的是段选择子

#figure(caption: [])[#image("images/chapter22-2.png", width: 60%)]

这里面的低端两位，此时表示 `CPL`，也就是当前所处的特权级，假如 `CS` 寄存器的后两位为`3`(`11b`)，就表示是当前处理器处于用户态这个特权级。

假如此时要跳转到另一处内存地址执行，在最终的汇编指令层面无非就是 `jmp`、`call` 和中断。以 `jmp` 跳转为例。
- 如果是短跳转，也就是直接 `jmp xxx`，那不涉及到段的变换，也就没有特权级检查这回事。
- 如果是长跳转，也就是 `jmp yyy:xxx`，这里的 `yyy` 就是另一个要跳转到的段的段选择子结构。这个结构仍然是一样的段选择子结构，只不过这里的低端两位，表示 `RPL`，也就是请求特权级，表示想请求的特权级是什么。同时，CPU 会拿这个段选择子去全局描述符表中寻找段描述符，从中找到段基址。
  - 段描述符里面有个 `DPL`，这表示目标代码段特权级，也就是即将要跳转过去的那个段的特权级。
  #figure(caption: [])[#image("images/chapter22-3.png", width: 80%)] 

总结：
#figure(caption: [])[#image("images/chapter22-4.png", width: 70%)] 

绝大多数情况下，要求 *CPL 必须等于 DPL*，才会跳转成功，否则就会报错。即当前代码所处段的特权级，必须要等于要跳转过去的代码所处的段的特权级，那就只能用户态往用户态跳，内核态往内核态跳。

这只是代码段跳转时所做的特权级检查，还有访问内存数据时也会有数据段的特权级检查。最终的效果是，处于*内核态的代码可以访问任何特权级的数据段，处于用户态的代码则只可以访问用户态的数据段*，这也就实现了内存数据读写的保护。

=== 特权级转换的方式

现在处于内核态，要怎么样才能跳转到用户态呢？Intel 设计了好多种特权级转换的方式，中断和中断返回就是其中的一种。

处于用户态的程序，通过触发中断，可以进入内核态，之后再通过中断返回，又可以恢复为用户态。系统调用就是这样，用户通过 `int 0x80` 中断指令触发了中断，CPU 切换至内核态，执行中断处理程序，之后中断程序返回，又从内核态切换回用户态。

有个问题是，当前就是处于内核态，并不是由一个用户态程序通过中断而切换到的内核态，那怎么回到用户态呢？
- 还是通过中断返回。Intel 设计的 CPU 就是可以没有中断也能中断返回，中断和中断返回的确是应该配套使用的，但也可以单独使用。

#figure(
```c
void main(void) {
    ...
    move_to_user_mode();
    ...
}

#define move_to_user_mode() \
_asm { \
    _asm mov eax,esp \
    _asm push 00000017h \
    _asm push eax \
    _asm pushfd \
    _asm push 0000000fh \
    _asm push offset l1 \
    _asm iretd /* 执行中断返回指令*/ \
_asm l1: mov eax,17h \
    _asm mov ds,ax \
    _asm mov es,ax \
    _asm mov fs,ax \
    _asm mov gs,ax \
}
```,
caption: [move_to_user_mode]
)

这个方法里直接就执行了中断返回指令 `iretd`。

中断返回理论上就是应该和中断配合使用的，而此时并不是真的发生了中断到这里，所以得假装发生了中断。中断发生时，CPU 会自动做如下的压栈操作。而中断返回时，CPU 又会把压栈的这些值返序赋值给响应的寄存器。这样就假装了中断的发生。

#figure(caption: [])[#image("images/chapter22-5.png", width: 55%)]

去掉错误码，刚好是五个参数，所以在代码中模仿 CPU 进行了五次压栈操作，*这样在执行 `iretd` 指令时，硬件会按顺序将刚刚压入栈中的数据，分别赋值给 `SS`、`ESP`、`EFLAGS`、`CS`、`EIP` 这几个寄存器*，这就感觉像是正确返回了一样，让其误以为这是通过中断进来的。

- 压入栈的 `CS` 和 `EIP` 就表示中断发生前代码所处的位置，这样中断返回后好继续去那里执行。
- 压入栈的 `SS` 和 `ESP` 表示中断发生前的栈的位置，这样中断返回后才好恢复原来的栈。
  #tip("Tip")[
  其中，特权级的转换，就体现在 `CS` 和 `SS` 寄存器的值里！
  ]

`CS` 和 `SS` 寄存器是段寄存器的一种，段寄存器里的值是段选择子
#figure(caption: [])[#image("images/chapter22-2.png", width: 60%)]

对着这个结构，看代码。

#figure(
```c
#define move_to_user_mode() \
_asm { \
    _asm mov eax,esp \
    _asm push 00000017h \ ; 给 SS 赋值
    _asm push eax \       ; 给 ESP 赋值
    _asm pushfd \         ; 给 EFLAGS 赋值
    _asm push 0000000fh \ ; 给 CS 赋值
    _asm push offset l1 \ ; 给 EIP 赋值
    _asm iretd /* 执行中断返回指令*/ \
_asm l1: mov eax,17h \
    _asm mov ds,ax \
    _asm mov es,ax \
    _asm mov fs,ax \
    _asm mov gs,ax \
}
```,
caption: [move_to_user_mode]
)

拿 `CS` 举例，给它赋值`0000000fh`(`0000000000001111b`)

最后两位 `11` 表示特权级为 `3`，即用户态。而刚刚说了，`CS` 寄存器里的特权级，表示 `CPL`，即当前处理器特权级。所以经过 `iretd` 返回之后，`CS` 的值就变成了它，而当前处理器特权级，也就变成了用户态特权级。

=== 除了改变特权级之外

`CS = 0000000000001111b`,最后两位表示用户态。倒数第三位 `TI` 表示，前面的描述符索引，是从 `GDT` 还是 `LDT` 中取，`1` 表示 `LDT`。

`CS`的`TI`为 `1`，表示从局部描述符表中取到代码段描述符。`sched_init`中将0号`LDT`作为当前`LDT`的索引记录在了CPU的`lldt`寄存器中.

#figure(
```c
#define lldt(n) __asm__("lldt %%ax"::"a" (_LDT(n)))

void sched_init(void) {
    ...
    lldt(0);
    ...
}
```,
caption: [sched_init - lldt]
)

经过内核的初始化之后，整个GDT和LDT表的设计如图：
#figure(caption: [])[#image("images/chapter22-6.png", width: 55%)]

再看代码
#figure(
```c
void main(void) {
    ...
    move_to_user_mode();
    ...
}

#define move_to_user_mode() \
_asm { \
    _asm mov eax,esp \
    _asm push 00000017h \ ; 给 SS 赋值
    _asm push eax \       ; 给 ESP 赋值
    _asm pushfd \         ; 给 EFLAGS 赋值
    _asm push 0000000fh \ ; 给 CS 赋值
    _asm push offset l1 \ ; 给 EIP 赋值
    _asm iretd /* 执行中断返回指令*/ \
_asm l1: mov eax,17h \
    _asm mov ds,ax \
    _asm mov es,ax \
    _asm mov fs,ax \
    _asm mov gs,ax \
}
```,
caption: [move_to_user_mode]
)

把 `EIP` 寄存器赋值为`l1`的地址，所以 `iretd` 之后 CPU 就乖乖去那里执行了。所以其实从效果上看，就是顺序往下执行，只不过利用了 `iretd` 做了些特权级转换等工作。

同理，这里的栈段 `ss` 和数据段 `ds`，都被赋值为了 `17h`(`0000000000010111b`)。可以得知`CPL=11b,TI=1b,index=10b`，用户态，`ldt`

== 进程调度: 调度信息

假如有三段代码被加载到内存中。
#figure(caption: [])[#image("images/chapter23-1.png", width: 40%)]

=== 整体流程设计

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

=== 上下文环境

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

=== 运行时间

如何判断一个进程该让出 CPU 了，切换到下一个进程呢？
- 每次时钟中断时都切换一次: 一不灵活，二完全依赖时钟中断的频率，危险。
- 给进程一个属性，叫剩余时间片，每次时钟中断来了之后都 `-1`，如果减到 `0` 了，就触发切换进程的操作。

在 Linux 0.11 里，这个属性就是 `counter`。

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

=== 优先级

`counter` 初始值该是多少呢？随着 `counter` 不断递减，减到 `0` 时，下一轮回中这个 `counter` 应该赋什么值呢？
 
就是 `counter` 的初始化问题，需要有一个属性来记录这个值。宏观想一下，这个值越大，那么 `counter` 就越大，那么每次轮到这个进程时，它在 CPU 中运行的时间就越长，也就是这个进程比其他进程得到了更多 CPU 运行的时间。那可以把这个值称为优先级。

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
 
=== 进程状态

有了上面那三个信息，就已经可以完成进程的调度了。如果操作系统让所有进程都得到同样的运行时间，连 `counter` 和 `priority` 都不用，就定一个固定值一直递减，减到 `0` 了就随机切一个新进程。这样就仅仅维护好寄存器的上下文信息 `tss` 就好了。
 
但总要不断优化以适应不同场景的用户需求的，那再优化一个细节。
 
一个进程中有一个读取硬盘的操作，发起读请求后，要等好久才能得到硬盘的中断信号。这个时间该进程再占用着 CPU 也没用，此时可以选择主动放弃 CPU ，然后再把状态标记为等待中。意思是告诉进程调度的代码，"先别调度我，因为我还在等硬盘的中断，现在轮到我了也没用，把机会给别人吧。"
 
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

== 进程调度: 定时器

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
- 如果时间片已经为零，则调用 `schedule()`，这就是进行进程调度的主干函数。

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

做个简化

#figure(
```c
void schedule(void) {
    int next = get_max_counter_and_runnable_thread();
    refresh_all_thread_counter();
    switch_to(next);
}
```,
caption: [schedule - 简化版]
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

== 通过`fork`看系统调用

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

关键指令就是一个 `0x80` 号软中断的触发，`int 80h`。其中还有一个 `eax` 寄存器里的参数是 `__NR_fork`，这也是个宏定义，值是`2`。

#tip("Tip")[
`0x80`中断是在`sched_init` 里面设置的`set_system_gate(0x80, &system_call);`
]

看这个`system_call` 的汇编代码，发现这么一行。

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

就是各种函数指针组成的一个数组。下标 `2` 位置处就是 `sys_fork`。通过系统调用这个中断，最终走到内核层面的函数是什么，就是 `sys_fork`。

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

=== `execve` -> `syscall3`

定义 `fork` 的系统调用模板函数时，用的是 `syscall0`，这个表示参数个数为 `0`，也就是 `sys_fork` 函数并不需要任何参数。在 `unistd.h` 头文件里，还定义了 `syscall0` ~ `syscall3` 一共四个宏。

```c
#define _syscall0(type,name)
#define _syscall1(type,name,atype,a)
#define _syscall2(type,name,atype,a,btype,b)
#define _syscall3(type,name,atype,a,btype,b,ctype,c)
```

这些参数放在哪里？以`execve`为例，是一个通常和 `fork` 在一起配合的函数，在之后的进程 1 创建进程 2 的过程中。

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

可以看到参数 `a` 被放在了 `ebx` 寄存器，参数 `b` 被放在了 `ecx` 寄存器，参数 `c` 被放在了 `edx` 寄存器。

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

只关注压栈的情况，因为 `system_call` 是通过`int 80h`这个软中断进来的，所以也属于中断的一种，具体说是属于特权级发生变化的，且没有错误码情况的中断，所以在这之前栈已经被压了 `SS`、`ESP`、`EFLAGS`、`CS`、`EIP` 这些值。

#figure(caption: [])[#image("images/chapter25-2.png", width: 50%)]
接下来 `system_call` 又压入了一些值，具体说来有 `ds`、`es`、`fs`、`edx`、`ecx`、`ebx`、`eax`。

`system_call.s` 上面的注释，Linus 贴心地写出了此时的堆栈状态。
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

随后在`do_execve`中，又通过 C 语言函数调用的约定，取走了 `filename`，`argv`，`envp` 等参数。

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

== `fork`中进程信息的复制

=== `sys_fork`
#figure(
```c
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

其实就是调用了两个函数。
- `find_empty_process`，找到空闲的进程槽位。
- `copy_process`，复制进程。

==== `find_empty_process`
#figure(caption: [])[#image("images/chapter26-1.png", width: 60%)]

存储进程的数据结构是一个 `task[64]` 数组，就是先在这个数组中找一个空闲的位置，准备存一个新的进程的结构 `task_struct`，通过 `copy_process` 复制原来的进程，也就是当前进程，即数组中位置 0 处的 `init_task.init`，也就是零号进程。

#figure(
```c
find_empty_process。

long last_pid = 0;

int find_empty_process(void) {
    int i;
    repeat:
        if ((++last_pid)<0) last_pid=1;
        for(i=0 ; i<64 ; i++)
            if (task[i] && task[i]->pid == last_pid) goto repeat;
    for(i=1 ; i<64; i++)
        if (!task[i])
            return i;
    return -EAGAIN;
}
```,
caption: [find_empty_process]
)

1. 判断 `++last_pid<0`，`<0`说明已经超过 `long` 的最大值了，重新赋值为 `1`，起到一个保护作用。
2. 一个 `for` 循环，看看刚刚的 `last_pid` 在所有 `task[]` 数组中，是否已经被某进程占用了。如果被占用了，那就回到步骤1，直到找到一个 `pid` 号没有被任何进程用为止。
3. 又是个 `for` 循环，刚刚已经找到一个可用的 `pid` 号了，就是再次遍历这个 `task[]` 试图找到一个空闲项，找到了就返回数组索引下标。
 
最终就返回 `task[]` 数组的索引，表示找到了一个空闲项，之后就开始往这里塞一个新的进程。

由于现在只有 0 号进程，且 `task[]` 除了 0 号索引位置，其他地方都是空的，所以这个方法运行完，`last_pid` 就是 `1`，也就是新进程被分配的 `pid` 就是 `1`，然后即将要加入的 `task[]` 数组的索引位置，也是 `1`。
 
==== `copy_process`
接下来看，怎么构造进程结构，塞到 `task[1]` 中？来看 `copy_process` 方法。

#figure(
```c
int copy_process(int nr,long ebp,long edi,long esi,long gs,long none,
        long ebx,long ecx,long edx,
        long fs,long es,long ds,
        long eip,long cs,long eflags,long esp,long ss)
{
    struct task_struct *p;
    int i;
    struct file *f;


    p = (struct task_struct *) get_free_page();
    if (!p)
        return -EAGAIN;
    task[nr] = p;
    *p = *current;  /* NOTE! this doesn't copy the supervisor stack */
    p->state = TASK_UNINTERRUPTIBLE;
    p->pid = last_pid;
    p->father = current->pid;
    p->counter = p->priority;
    p->signal = 0;
    p->alarm = 0;
    p->leader = 0;      /* process leadership doesn't inherit */
    p->utime = p->stime = 0;
    p->cutime = p->cstime = 0;
    p->start_time = jiffies;
    p->tss.back_link = 0;
    p->tss.esp0 = PAGE_SIZE + (long) p;
    p->tss.ss0 = 0x10;
    p->tss.eip = eip;
    p->tss.eflags = eflags;
    p->tss.eax = 0;
    p->tss.ecx = ecx;
    p->tss.edx = edx;
    p->tss.ebx = ebx;
    p->tss.esp = esp;
    p->tss.ebp = ebp;
    p->tss.esi = esi;
    p->tss.edi = edi;
    p->tss.es = es & 0xffff;
    p->tss.cs = cs & 0xffff;
    p->tss.ss = ss & 0xffff;
    p->tss.ds = ds & 0xffff;
    p->tss.fs = fs & 0xffff;
    p->tss.gs = gs & 0xffff;
    p->tss.ldt = _LDT(nr);
    p->tss.trace_bitmap = 0x80000000;
    if (last_task_used_math == current)
        __asm__("clts ; fnsave %0"::"m" (p->tss.i387));
    if (copy_mem(nr,p)) {
        task[nr] = NULL;
        free_page((long) p);
        return -EAGAIN;
    }
    for (i=0; i<NR_OPEN;i++)
        if (f=p->filp[i])
            f->f_count++;
    if (current->pwd)
        current->pwd->i_count++;
    if (current->root)
        current->root->i_count++;
    if (current->executable)
        current->executable->i_count++;
    set_tss_desc(gdt+(nr<<1)+FIRST_TSS_ENTRY,&(p->tss));
    set_ldt_desc(gdt+(nr<<1)+FIRST_LDT_ENTRY,&(p->ldt));
    p->state = TASK_RUNNING;    /* do this last, just in case */
    return last_pid;
}
```,
caption: [copy_process]
)

大部分都是 `tss` 结构的复制，以及一些无关紧要的分支，简化下。

#figure(
```c
int copy_process(int nr, ...) {
    struct task_struct p = 
        (struct task_struct *) get_free_page();
    task[nr] = p;
    *p = *current;

    p->state = TASK_UNINTERRUPTIBLE;
    p->pid = last_pid;
    p->counter = p->priority;
    ..
    p->tss.edx = edx;
    p->tss.ebx = ebx;
    p->tss.esp = esp;
    ...
    copy_mem(nr,p);
    ...
    set_tss_desc(gdt+(nr<<1)+FIRST_TSS_ENTRY,&(p->tss));
    set_ldt_desc(gdt+(nr<<1)+FIRST_LDT_ENTRY,&(p->ldt));
    p->state = TASK_RUNNING;
    return last_pid;
}
```,
caption: [copy_process - 简化版]
)

首先 `get_free_page` 会在主内存末端申请一个空闲页面，就是遍历 `mem_map[]` 这个数组，找出值为零的项。然后把该项置为 1，表示该页已经被使用。最后，算出这个页的内存起始地址，返回。拿到的这个内存起始地址，就给了 `task_struct` 结构的 `p`。

#figure(caption: [])[#image("images/chapter26-2.png", width: 70%)]

#figure(
```c
int copy_process(int nr, ...) {
    struct task_struct p = 
        (struct task_struct *) get_free_page();
    task[nr] = p;
    *p = *current;
    ...
}
```,
caption: [copy_process - get_free_page]
)

一个进程结构 `task_struct` 就在内存中有了一块空间，此时还没有赋值具体的字段。

首先将这个 `p` 记录在进程管理结构 `task[]` 中。下一句 `*p = *current` ，就是把当前进程，也就是 0 号进程的 `task_struct` 的全部值都复制给即将创建的进程 `p`，这里是个*赋值*操作，目前它们两者就完全一样了。最后的内存布局的效果：

#figure(caption: [])[#image("images/chapter26-3.png", width: 70%)]

进程 1 和进程 0 目前是完全复制的关系，但有一些值是需要个性化处理的，不一样的值，一部分是 `state`，`pid`，`counter` 这种进程的元信息，另一部分是 `tss` 里面保存的各种寄存器的信息，即*上下文*。下面的代码就是把这些不一样的值覆盖掉。


#figure(
```c
int copy_process(int nr, ...) {
    ...
    p->state = TASK_UNINTERRUPTIBLE;
    p->pid = last_pid;
    p->counter = p->priority;
    ..
    p->tss.edx = edx;
    p->tss.ebx = ebx;
    p->tss.esp = esp;
    ...
    p->tss.esp0 = PAGE_SIZE + (long) p;
    p->tss.ss0 = 0x10;
    ...
}
```,
caption: [copy_process - 个性化处理]
)

`ss0` 和 `esp0`的赋值有些特殊，这个表示 `0` 特权级也就是内核态时的 `ss:esp` 的指向。根据代码，其含义是将代码在内核态时使用的堆栈栈顶指针指向进程 `task_struct` 所在的 4K 内存页的最顶端，而且之后的每个进程都是这样被设置的。

#figure(caption: [])[#image("images/chapter26-4.png", width: 40%)]

== 通过`fork`看进程的内存规划

来看`fork` 函数剩下的另一半，即 `copy_mem`。

#figure(
```c
int copy_process(int nr, ...) {
    ...
    copy_mem(nr,p);
    ...
}
```,
caption: [copy_process - copy_mem]
)

#figure(
```c
int copy_mem(int nr,struct task_struct * p) {
    // 局部描述符表 LDT 赋值
    unsigned long old_data_base,new_data_base,data_limit;
    unsigned long old_code_base,new_code_base,code_limit;
    code_limit = get_limit(0x0f);
    data_limit = get_limit(0x17);
    new_code_base = nr * 0x4000000;
    new_data_base = nr * 0x4000000;
    set_base(p->ldt[1],new_code_base);
    set_base(p->ldt[2],new_data_base);
    // 拷贝页表
    old_code_base = get_base(current->ldt[1]);
    old_data_base = get_base(current->ldt[2]);
    copy_page_tables(old_data_base,new_data_base,data_limit);
    return 0;
}
```,
caption: [copy_mem]
)

就是新进程 `LDT` 表项的赋值，以及页表的拷贝。

=== LDT 的赋值

#figure(caption: [])[#image("images/chapter27-1.png", width: 50%)]

给进程 0 准备的 `LDT` 的代码段和数据段，段基址都是 0，段限长是 640K。
给进程 1，也就是现在正在 `fork` 的这个进程，其代码段和数据段还没有设置。

所以第一步，局部描述符表 `LDT` 的赋值，就是给上图中那两个还未设置的代码段和数据段赋值。其中段限长，就是取自进程 0 设置好的段限长，也就是 640K。

#figure(
```c
int copy_mem(int nr,struct task_struct * p) {
    ...
    code_limit = get_limit(0x0f);
    data_limit = get_limit(0x17);
    ...
}
```,
caption: [copy_mem - 段限长]
)

而段基址取决于当前是几号进程，也就是 `nr` 的值。

#figure(
```c
int copy_mem(int nr,struct task_struct * p) {
    ...
    new_code_base = nr * 0x4000000;
    new_data_base = nr * 0x4000000;
    ...
}
```,
caption: [copy_mem - 段基址]
)

这里的 `0x4000000` 等于 64M。(即今后每个进程通过段基址的手段，分别在线性地址空间中占用 64M 的空间（暂不考虑段限长），且紧挨着。)

接着就把 LDT 设置进了 LDT 表里。

#figure(
```c
int copy_mem(int nr,struct task_struct * p) {
    ...
    set_base(p->ldt[1],new_code_base);
    set_base(p->ldt[2],new_data_base);
    ...
}
```,
caption: [copy_mem - 添加到ldt表]
)

最终效果：
#figure(caption: [])[#image("images/chapter27-2.png", width: 50%)]

经过以上的步骤，就通过分段的方式，将进程映射到了相互隔离的线性地址空间里，这就是*段式管理*。Linux 0.11 不但是分段管理，也开启了分页管理，最终形成段页式的管理方式。

=== `copy_page_tables`: 页表的复制

页表的复制也是 `copy_mem` 函数里的最后一行代码。

#figure(
```c
int copy_mem(int nr,struct task_struct * p) {
    ...
    // old=0, new=64M, limit=640K
    copy_page_tables(old_data_base,new_data_base,data_limit)
}
```,
caption: [copy_mem - copy_page_tables]
)

原来进程 0 有一个页目录表和四个页表，将线性地址空间的 0-16M 原封不动映射到了物理地址空间的 0-16M。

#figure(caption: [])[#image("images/chapter27-3.png", width: 30%)]

那么新诞生的这个进程 1，也需要一套映射关系的页表。

#figure(
```c
/*
 *  Well, here is one of the most complicated functions in mm. It
 * copies a range of linerar addresses by copying only the pages.
 * Let's hope this is bug-free, 'cause this one I don't want to debug :-)
 */
int copy_page_tables(unsigned long from,unsigned long to,long size)
{
    unsigned long * from_page_table;
    unsigned long * to_page_table;
    unsigned long this_page;
    unsigned long * from_dir, * to_dir;
    unsigned long nr;

    from_dir = (unsigned long *) ((from>>20) & 0xffc);
    to_dir = (unsigned long *) ((to>>20) & 0xffc);
    size = ((unsigned) (size+0x3fffff)) >> 22;
    for( ; size-->0 ; from_dir++,to_dir++) {
        if (!(1 & *from_dir))
            continue;
        from_page_table = (unsigned long *) (0xfffff000 & *from_dir);
        to_page_table = (unsigned long *) get_free_page()
        *to_dir = ((unsigned long) to_page_table) | 7;
        nr = (from==0)?0xA0:1024;
        for ( ; nr-- > 0 ; from_page_table++,to_page_table++) {
            this_page = *from_page_table;
            if (!(1 & this_page))
                continue;
            this_page &= ~2;
            *to_page_table = this_page;
            if (this_page > LOW_MEM) {
                *from_page_table = this_page;
                this_page -= LOW_MEM;
                this_page >>= 12;
                mem_map[this_page]++;
            }
        }
    }
    invalidate();
    return 0;
}
```,
caption: [copy_page_tables]
)

Linus 注释：

#blockquote[
"这部分是内存管理中最复杂的代码，希望这段代码没有错误（bug-free），因为我实在不想调试它！"
]

现在进程 0 的线性地址空间是 0 - 64M，进程 1 的线性地址空间是 64M - 128M。现在要造一个进程 1 的页表，使得进程 1 和进程 0 最终被映射到的物理空间都是 0 - 64M，这样进程 1 才能顺利运行起来。

#figure(caption: [])[#image("images/chapter27-4.png", width: 40%)]

最终的效果就是：

假设现在正在运行进程 0，代码中给出一个虚拟地址 `0x03`，由于进程 0 的 `LDT` 中代码段基址是 `0`，所以线性地址也是 `0x03`，最终由进程 0 页表映射到物理地址 `0x03` 处。

假设现在正在运行进程 1，代码中给出一个虚拟地址 `0x03`，由于进程 1 的 `LDT` 中代码段基址是 `64M`，所以线性地址是 `64M + 3`，最终由进程 1 页表映射到物理地址也同样是 `0x03` 处。

#figure(caption: [])[#image("images/chapter27-5.png", width: 50%)]

即，*进程 0 和进程 1 目前共同映射物理内存的前 640K 的空间*。

如何将不同地址通过不同页表映射到相同物理地址空间，举个刚刚的例子。
- 刚刚的进程 1 的线性地址 64M + 0x03 用二进制表示是： `0000010000_0000000000_000000000011b`
- 刚刚的进程 0 的线性地址 0x03 用二进制表示是： `0000000000_0000000000_000000000011b`

根据分页机制的转化规则，前 10 位表示页目录项，中间 10 位表示页表项，后 12 位表页内偏移。
- 进程 1 要找的是页目录项 16 中的第 0 号页表
- 进程 0 要找的是页目录项 0 中的第 0 号页表

那只要让这俩最终找到的两个页表里的数据一模一样即可。

=== 页目录项/页表项的结构

#figure(caption: [])[#image("images/chapter27-6.png", width: 70%)]

其中 `RW` 位表示读写状态，`0` 表示只读（或可执行），`1`表示可读写（或可执行）。当然，在内核态也就是 `0` 特权级时，这个标志位是没用的。

#figure(
```c
int copy_page_tables(unsigned long from,unsigned long to,long size) {
    ...
    for( ; size-->0 ; from_dir++,to_dir++) {
        ...
        for ( ; nr-- > 0 ; from_page_table++,to_page_table++) {
            ...
            this_page &= ~2;
            ...
            if (this_page > LOW_MEM) {
                *from_page_table = this_page;
                ...
            }
        }
    }
    ...
}
```,
caption: [copy_page_tables]
)

`~2` 表示取反，`2` 用二进制表示是 `10b`，取反就是 `01b`，其目的是把 `this_page` 也就是当前的页表的 `RW` 位置零，也就是是把该页变成只读。 而 `*from_page_table = this_page` 表示又把源页表也变成只读。

也就是说，经过 `fork` 创建出的新进程，其页表项都是只读的，而且导致源进程的页表项也变成了只读。这个就是写时复制的基础，新老进程一开始共享同一个物理内存空间，如果只有读，那就相安无事，但如果任何一方有写操作，由于页面是只读的，将触发缺页中断，然后就会分配一块新的物理内存给产生写操作的那个进程，此时这一块内存就不再共享了。

== `fork`的写时复制

#figure(caption: [])[#image("images/chapter28-1.png", width: 60%)]
#figure(caption: [])[#image("images/chapter28-2.png", width: 60%)]

#figure(
```c
int copy_page_tables(...) {
    ...
    // 源页表和新页表一样
    this_page = *from_page_table;
    ...
    // 源页表和新页表均置为只读
    this_page &= ~2;
    *from_page_table = this_page;
    ...
}
```,
caption: [copy_page_tables - 设置只读]
)

就是把页表的`R/W`置0了。
#figure(caption: [])[#image("images/chapter28-3.png", width: 60%)]

再次对这块物理地址空间进行写操作时，就不允许了。但不允许并不是真的不允许，Intel 会触发一个缺页中断，具体是 `0x14` 号中断，中断处理程序里边怎么处理，那就由 Linux 源码自由发挥了。

Linux 0.11 的缺页中断处理函数的开头是用汇编写的，这里选 Linux 1.0 的代码，逻辑是一样的。

#figure(
```c
void do_page_fault(..., unsigned long error_code) {
    ...
    if (error_code & 1)
        do_wp_page(error_code, address, current, user_esp);
    else
        do_no_page(error_code, address, current, user_esp);
    ...
}
```,
caption: [do_page_fault]
)

可以看出，根据中断异常码 `error_code` 的不同，有不同的逻辑。

#figure(caption: [])[#image("images/chapter28-4.png", width: 70%)]

当 `error_code` 的第 0 位，也就是存在位为 0 时，会走 `do_no_page` 逻辑，其余情况，均走 `do_wp_page` 逻辑。

`fork` 的时候只是将读写位变成了只读，存在位仍然是 1 没有动，所以会走 `do_wp_page` 逻辑。

#figure(
```c
void do_wp_page(unsigned long error_code,unsigned long address) {
    // 后面这一大坨计算了 address 在页表项的指针
    un_wp_page((unsigned long *)
        (((address>>10) & 0xffc) + (0xfffff000 &
        *((unsigned long *) ((address>>20) &0xffc)))));
}

void un_wp_page(unsigned long * table_entry) {
    unsigned long old_page,new_page;
    old_page = 0xfffff000 & *table_entry;
    // 只被引用一次，说明没有被共享，那只改下读写属性就行了
    if (mem_map[MAP_NR(old_page)]==1) {
        *table_entry |= 2;
        invalidate();
        return;
    }
    // 被引用多次，就需要复制页表了

    new_page=get_free_page()；
    mem_map[MAP_NR(old_page)]--;
    *table_entry = new_page | 7;
    invalidate();
    copy_page(old_page,new_page);
}

// 刷新页变换高速缓冲宏函数
#define invalidate() \
__asm__("movl %%eax,%%cr3"::"a" (0))
```,
caption: [do_wp_page]
)

刚刚 `fork` 完一个进程：

#figure(caption: [])[#image("images/chapter28-3.png", width: 60%)]

这是对着这个物理空间范围，写一个值，就会触发上述函数。假如是进程 2 写的。显然此时这个物理空间被引用了大于 1 次，所以要复制页面。

```c
new_page=get_free_page()；
```

并且更改页面只读属性为可读写。

```c
*table_entry = new_page | 7;
```

#figure(caption: [])[#image("images/chapter28-5.png", width:60%)]

那此时如果进程 1 再写呢？那么引用次数就等于 1 了，只需要更改下页属性即可，不用进行页面复制操作。
```c
if (mem_map[MAP_NR(old_page)]==1) ...
```
#figure(caption: [])[#image("images/chapter28-6.png", width: 60%)]

缺页中断的处理过程中，除了写时复制原理的 `do_wp_page`，还有个 `do_no_page`，是在页表项的存在位 `P` 为 `0` 时触发的。 这个和进程按需加载内存有关，如果还没加载到内存，会通过这个函数将磁盘中的数据复制到内存来


