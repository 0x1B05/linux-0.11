#import "../template.typ": *

= 进程调度(`sched_init`)

`sched_init`前两行代码初始化了下 `TSS` 和 `LDT`。

#figure(
```c
void sched_init(void) {
    set_tss_desc(gdt+4, &(init_task.task.tss));
    set_ldt_desc(gdt+5, &(init_task.task.ldt));
    ...
}
```,
caption: [sched_init - part1]
)

回想先前的`gdt`: 
#figure(caption: [])[#image("images/chapter18-1.png",width: 70%)]

#definition("Definition")[
`TSS` 叫任务状态段，用来保存和恢复进程的上下文的。
#figure(
```c
struct tss_struct{
    long back_link;
    long esp0;
    long ss0;
    long esp1;
    long ss1;
    long esp2;
    long ss2;
    long cr3;
    long eip;
    long eflags;
    long eax, ecx, edx, ebx;
    long esp;
    long ebp;
    long esi;
    long edi;
    long es;
    long cs;
    long ss;
    long ds;
    long fs;
    long gs;
    long ldt;
    long trace_bitmap;
    struct i387_struct i387;
};
```,
caption: [tss_struct]
)
]

#definition("Definition")[
`LDT` 叫局部描述符表，与 `GDT` 全局描述符表相对应的，内核态的代码用 `GDT` 里的数据段和代码段，用户进程的代码用每个用户进程自己的 `LDT` 里的数据段和代码段。
]

#figure(caption: [])[#image("images/chapter18-2.png", width: 70%)]

#figure(
```c
struct desc_struct {
    unsigned long a,b;
}

struct task_struct * task[64] = {&(init_task.task), };

void sched_init(void) {
    ...
    int i;
    struct desc_struct * p;
        p = gdt+6;
    for(i=1;i<64;i++) {
        task[i] = NULL;
        p->a=p->b=0;
        p++;
        p->a=p->b=0;
        p++;
    }
    ...
}
```,
caption: [sched_init - part2]
)

这段代码有个循环，干了两件事。

- 一个是给一个长度为 `64`，结构为 `task_struct`(进程的信息) 的数组 `task` 附上初始值。
  #figure(caption: [])[#image("images/chapter18-3.png", width:70%)]
  #figure(
  ```c
  struct task_struct {
  /* these are hardcoded - don't touch */
      long state; /* -1 unrunnable, 0 runnable, >0 stopped */
      long counter;
      long priority;
      long signal;
      struct sigaction sigaction[32];
      long blocked; /* bitmap of masked signals */
    /* various fields */
      int exit_code;
      unsigned long start_code,end_code,end_data,brk,start_stack;
      long pid,father,pgrp,session,leader;
      unsigned short uid,euid,suid;
      unsigned short gid,egid,sgid;
      long alarm;
      long utime,stime,cutime,cstime,start_time;
      unsigned short used_math;
    /* file system info */
      int tty;  /* -1 if no tty, so it must be signed */
      unsigned short umask;
      struct m_inode * pwd;
      struct m_inode * root;
      struct m_inode * executable;
      unsigned long close_on_exec;
      struct file * filp[NR_OPEN];
    /* ldt for this task 0 - zero 1 - cs 2 - ds&ss */
      struct desc_struct ldt[3];
    /* tss for this task */
      struct tss_struct tss;
  };
  ```,
  caption: [task_struct]
  )
- 另一件事，是给 `gdt` 剩下的位置填充上 `0`，也就是把剩下留给 `TSS` 和 `LDT` 的描述符都先附上空值。
  #figure(caption: [])[#image("images/chapter18-4.png", width: 70%)]
  以后每创建一个新进程，就会在后面添加一组 `TSS` 和 `LDT` 表示这个进程的任务状态段以及局部描述符表信息。

那为什么一开始就先有了一组 `TSS` 和 `LDT` 呢？现在也没创建进程呀。现在虽然还没有建立起进程调度的机制，但我们正在运行的代码就是会作为未来的一个进程的指令流。也就是当未来进程调度机制一建立起来，正在执行的代码就会化身成为进程 0 的代码。所以我们需要提前把这些未来会作为进程 0 的信息写好。

#figure(
```c
#define ltr(n) __asm__("ltr %%ax"::"a" (_TSS(n)))
#define lldt(n) __asm__("lldt %%ax"::"a" (_LDT(n)))

void sched_init(void) {
    ...
    ltr(0);
    lldt(0);
    ...
}
```,
caption: [sched_init - part3]
)

#tip("Tip")[
- `lidt` 指令：给 `idtr` 寄存器赋值，告诉 CPU 中断描述符表 `idt` 在内存的位置
- `lgdt` 指令：给 `gdtr` 寄存器赋值，告诉 CPU 全局描述符表 `gdt` 在内存的位置。
]

这里，`ltr` 是给 `tr` 寄存器赋值，以告诉 CPU 任务状态段 `TSS` 在内存的位置；`lldt` 一个是给 `ldt` 寄存器赋值，以告诉 CPU 局部描述符 `LDT` 在内存的位置。
#figure(caption: [])[#image("images/chapter18-5.png", width:70%)]
CPU 之后就能通过 `tr` 寄存器找到当前进程的任务状态段信息，也就是上下文信息，以及通过 `ldt` 寄存器找到当前进程在用的局部描述符表信息。

#figure(
```c
void sched_init(void) {
    ...
    outb_p(0x36,0x43);      /* binary, mode 3, LSB/MSB, ch 0 */
    outb_p(LATCH & 0xff , 0x40);    /* LSB */
    outb(LATCH >> 8 , 0x40);    /* MSB */
    set_intr_gate(0x20,&timer_interrupt);
    outb(inb_p(0x21)&~0x01,0x21);
    set_system_gate(0x80,&system_call);
    ...
}
```,
caption: [sched_init - part4]
)

四行端口读写代码，两行设置中断代码。

- 端口读写：这次交互的外设是一个可编程定时器的芯片，这四行代码就开启了这个定时器，之后*这个定时器变会持续的、以一定频率的向 CPU 发出中断信号*。
- 设置中断：
  - 第一个就是时钟中断，中断号为 `0x20`，中断处理程序为 `timer_interrupt`。那么每次定时器向 CPU 发出中断后，便会执行这个函数。
  - 第二个设置的中断叫系统调用 `system_call`，中断号是 `0x80`，所有用户态程序想要调用内核提供的方法，都需要基于这个系统调用来进行。

到目前为止，中断已经设置了不少了，我们现在看看所设置好的中断有哪些。


#align(center, 
three-line-table[
|中断号   | 中断处理函数|
| -       | - |
|0 ~ 0x10 | trap_init 里设置的一堆(除零异常...)|
|0x20     |timer_interrupt|
|0x21     |keyboard_interrupt|
|0x80     |system_call|
]
)



#pagebreak()
