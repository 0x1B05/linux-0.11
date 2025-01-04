#import "../template.typ":*

= fork的写时复制

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

我们 `fork` 的时候只是将读写位变成了只读，存在位仍然是 1 没有动，所以会走 `do_wp_page` 逻辑。

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

这是对着这个物理空间范围，写一个值，就会触发上述函数。假如是进程 2 写的。

显然此时这个物理空间被引用了大于 1 次，所以要复制页面。

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

#pagebreak()
