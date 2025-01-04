#import "../template.typ":*

= fork中进程信息的复制

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

#figure(caption: [])[#image("images/chapter26-1.png", width: 60%)]
因为存储进程的数据结构是一个 `task[64]` 数组，就是先在这个数组中找一个空闲的位置，准备存一个新的进程的结构 `task_struct`，通过 `copy_process` 复制原来的进程，也就是当前进程，即数组中位置 0 处的 `init_task.init`，也就是零号进程。

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

1. 判断 `++last_pid` 是不是`<0`了，`<0`说明已经超过 `long` 的最大值了，重新赋值为 `1`，起到一个保护作用。
2. 一个 `for` 循环，看看刚刚的 `last_pid` 在所有 `task[]` 数组中，是否已经被某进程占用了。如果被占用了，那就回到步骤1，直到找到一个 `pid` 号没有被任何进程用为止。
3. 又是个 `for` 循环，刚刚已经找到一个可用的 `pid` 号了，就是再次遍历这个 `task[]` 试图找到一个空闲项，找到了就返回数组索引下标。
 
最终就返回 `task[]` 数组的索引，表示找到了一个空闲项，之后就开始往这里塞一个新的进程。

由于现在只有 0 号进程，且 `task[]` 除了 0 号索引位置，其他地方都是空的，所以这个方法运行完，`last_pid` 就是 `1`，也就是新进程被分配的 `pid` 就是 `1`，然后即将要加入的 `task[]` 数组的索引位置，也是 `1`。
 
那接下来就看，怎么构造进程结构，塞到 `task[1]` 中？来看 `copy_process` 方法。

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

#figure(caption: [])[#image("images/chapter26-2.png", width: 70%)]
首先 `get_free_page` 会在主内存末端申请一个空闲页面，就是遍历 `mem_map[]` 这个数组，找出值为零的项，就表示找到了空闲的一页内存。然后把该项置为 1，表示该页已经被使用。最后，算出这个页的内存起始地址，返回。拿到的这个内存起始地址，就给了 `task_struct` 结构的 `p`。

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
首先将这个 `p` 记录在进程管理结构 `task[]` 中。下一句 `*p = *current` ，就是把当前进程，也就是 0 号进程的 `task_struct` 的全部值都复制给即将创建的进程 `p`，目前它们两者就完全一样了。最后的内存布局的效果：
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

#figure(caption: [])[#image("images/chapter26-4.png", width: 50%)]

#pagebreak()
