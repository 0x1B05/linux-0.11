#import "../template.typ": *

= 操作系统就用一张大表管理内存

进入 `mem_init` 函数。

#figure(
```c
#define LOW_MEM 0x100000
#define PAGING_MEMORY (15*1024*1024)
#define PAGING_PAGES (PAGING_MEMORY>>12)
#define MAP_NR(addr) (((addr)-LOW_MEM)>>12)
#define USED 100

static long HIGH_MEMORY = 0;
static unsigned char mem_map[PAGING_PAGES] = { 0, };

// start_mem = 2 * 1024 * 1024
// end_mem = 8 * 1024 * 1024
void mem_init(long start_mem, long end_mem)
{
    int i;
    HIGH_MEMORY = end_mem;
    for (i=0 ; i<PAGING_PAGES ; i++)
        mem_map[i] = USED;
    i = MAP_NR(start_mem);
    end_mem -= start_mem;
    end_mem >>= 12;
    while (end_mem-->0)
        mem_map[i++]=0;
}
```,
caption: [mem_init]
)

就是给一个 `mem_map` 数组的各个位置上赋了值，这个数组的每个元素都代表一个 4K 内存是否空闲（准确说是使用次数），而且显示全部赋值为 `USED` 也就是 `100`(占用了 `100` 次)，然后对其中一部分又赋值为了 `0`表示未被使用(也即使用次数为`0`)。

就是准备了一个表，记录了哪些内存被占用了，哪些内存没被占用。还是一张图就看明白了，我们仍然假设内存总共只有 8M。
#figure(caption: [])[#image("images/chapter13-1.png", width: 70%)]

- 1M 以下的内存这个数组干脆没有记录，这里的内存是无权管理的，也就是没有权利申请和释放，因为这个区域是内核代码所在的地方。
- 1M 到 2M 这个区间是*缓冲区*，2M 是缓冲区的末端，这些地方不是主内存区域，因此直接标记为 `USED`，产生的效果就是*无法再被分配了*。
- 2M 以上的空间是*主内存区域*，而主内存目前没有任何程序申请，所以初始化时统统都是零，未来等着应用程序去申请和释放这里的内存资源。

在 `memory.c` 文件中有个函数 `get_free_page()`，用于在主内存区中申请一页空闲内存页，并返回物理内存页的起始地址。比如在 `fork` 子进程的时候，会调用 `copy_process` 函数来复制进程的结构信息，其中有一个步骤就是要申请一页内存，用于存放进程结构信息 `task_struct`。

#figure(
```c
int copy_process(...) {
    struct task_struct *p;
    ...
    p = (struct task_struct *) get_free_page();
    ...
}
```,
caption: [copy_process]
)

`get_free_page` 的具体实现，是内联汇编代码，注意它里面就有 `mem_map` 结构的使用。

#figure(
```c
unsigned long get_free_page(void) {
    register unsigned long __res asm("ax");
    __asm__(
        "std ; repne ; scasb\n\t"
        "jne 1f\n\t"
        "movb $1,1(%%edi)\n\t"
        "sall $12,%%ecx\n\t"
        "addl %2,%%ecx\n\t"
        "movl %%ecx,%%edx\n\t"
        "movl $1024,%%ecx\n\t"
        "leal 4092(%%edx),%%edi\n\t"
        "rep ; stosl\n\t"
        "movl %%edx,%%eax\n"
        "1:"
        :"=a" (__res)
        :"0" (0),"i" (LOW_MEM),"c" (PAGING_PAGES),
        "D" (mem_map + PAGING_PAGES-1)
        :"di","cx","dx");
    return __res;
}
```,
caption: [get_free_page]
)
就是选择 `mem_map` 中首个空闲页面，并标记为已使用。
#pagebreak()
