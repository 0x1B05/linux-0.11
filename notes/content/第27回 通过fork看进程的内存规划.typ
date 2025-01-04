#import "../template.typ":*

= 通过fork看进程的内存规划

`fork` 函数的一半已经讲完了，来看另一半，即 `copy_mem` 函数。

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

其实就是新进程 `LDT` 表项的赋值，以及页表的拷贝。

== LDT 的赋值

#figure(caption: [])[#image("images/chapter27-1.png", width: 50%)]

我们给进程 0 准备的 LDT 的代码段和数据段，段基址都是 0，段限长是 640K。
给进程 1，也就是我们现在正在 fork 的这个进程，其代码段和数据段还没有设置。

所以第一步，局部描述符表 LDT 的赋值，就是给上图中那两个还未设置的代码段和数据段赋值。其中段限长，就是取自进程 0 设置好的段限长，也就是 640K。

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

== 页表的复制 

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

Linus 注释说：

#blockquote[
"这部分是内存管理中最复杂的代码，希望这段代码没有错误（bug-free），因为我实在不想调试它！"
]

现在进程 0 的线性地址空间是 0 - 64M，进程 1 的线性地址空间是 64M - 128M。我们现在要造一个进程 1 的页表，使得进程 1 和进程 0 最终被映射到的物理空间都是 0 - 64M，这样进程 1 才能顺利运行起来，不然就乱套了。
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

== 页目录项/页表项的结构
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

#pagebreak()
