#import "../template.typ": *

= `main`里面的初始化

== 概览

#figure(
```c
void main(void) {
    ROOT_DEV = ORIG_ROOT_DEV;
    drive_info = DRIVE_INFO;
    memory_end = (1<<20) + (EXT_MEM_K<<10);
    memory_end &= 0xfffff000;
    if (memory_end > 16*1024*1024)
        memory_end = 16*1024*1024;
    if (memory_end > 12*1024*1024) 
        buffer_memory_end = 4*1024*1024;
    else if (memory_end > 6*1024*1024)
        buffer_memory_end = 2*1024*1024;
    else
        buffer_memory_end = 1*1024*1024;
    main_memory_start = buffer_memory_end;
    mem_init(main_memory_start,memory_end);
    trap_init();
    blk_dev_init();
    chr_dev_init();
    tty_init();
    time_init();
    sched_init();
    buffer_init(buffer_memory_end);
    hd_init();
    floppy_init();
    sti();
    move_to_user_mode();
    if (!fork()) {
        init();
    }
    for(;;) pause();
}
```,
caption: [main]
)

=== part1: 参数的取值和计算

第一部分是一些参数的取值和计算。`ROOT_DEV` 为系统的根文件设备号，`drive_info` 为之前 `setup.s` 程序获取并存储在内存 `0x90000` 处的设备信息，以及通过计算得到的内存边界 `main_memory_start`, `main_memory_end`, `buffer_memory_start`, `buffer_memory_end`。

#figure(
```c
void main(void) {
    ROOT_DEV = ORIG_ROOT_DEV;
    drive_info = DRIVE_INFO;
    memory_end = (1<<20) + (EXT_MEM_K<<10);
    memory_end &= 0xfffff000;
    if (memory_end > 16*1024*1024)
        memory_end = 16*1024*1024;
    if (memory_end > 12*1024*1024) 
        buffer_memory_end = 4*1024*1024;
    else if (memory_end > 6*1024*1024)
        buffer_memory_end = 2*1024*1024;
    else
        buffer_memory_end = 1*1024*1024;
    main_memory_start = buffer_memory_end;
    ...
}
```,
caption: [main - part1]
)

#tip("Tip")[
设备参数信息都是由 `setup.s` 这个汇编程序调用 BIOS 中断获取的各个设备的信息，并保存在约定好的内存地址 `0x90000` 处。
]

=== part2: `init`

第二部分是各种初始化 `init` 操作。包括内存初始化 `mem_init`，中断初始化 `trap_init`、进程调度初始化 `sched_init` 等等。

#figure(
```c
void main(void) {
    ...
    mem_init(main_memory_start,memory_end);
    trap_init();
    blk_dev_init();
    chr_dev_init();
    tty_init();
    time_init();
    sched_init();
    buffer_init(buffer_memory_end);
    hd_init();
    floppy_init();
    ...
}
```,
caption: [main - part2]
)

 
=== part3: 第一个用户进程
第三部分是切换到用户态模式，并在一个新的进程中做一个最终的初始化 `init`。这个 `init` 函数里会创建出一个进程，设置终端的标准 IO，并且再创建出一个执行 shell 程序的进程用来接受用户的命令，到这里其实就出现了熟悉的shell画面。

#figure(
```c
void main(void) {
    ...
    sti();
    move_to_user_mode();
    if (!fork()) {
        init();
    }
    ...
}
```,
caption: [main - part3]
)

=== part4: 死循环

第四部分是个死循环，如果没有任何任务可以运行，操作系统会一直等待。

#figure(
```c
void main(void) {
    ...
    for(;;) pause();
}
```,
caption: [main - part4]
)

内存布局图。
#figure(caption: [])[#image("images/chapter11-1.png", width: 60%)]

== `mem_init`: 

=== 准备工作: 管理内存前先划分出三个边界值

#figure(
```c
void main(void) {
    ...
    memory_end = (1<<20) + (EXT_MEM_K<<10);
    memory_end &= 0xfffff000;
    if (memory_end > 16*1024*1024)
        memory_end = 16*1024*1024;
    if (memory_end > 12*1024*1024) 
        buffer_memory_end = 4*1024*1024;
    else if (memory_end > 6*1024*1024)
        buffer_memory_end = 2*1024*1024;
    else
        buffer_memory_end = 1*1024*1024;
    main_memory_start = buffer_memory_end;
    ...
}
```,
caption: [main - memory]
)
#h(2em)细看发现这段代码只是为了计算出三个变量： `main_memory_start`, `memory_end`, `buffer_memory_end`

而读最后一行代码发现，其实`main_memory_start`, `buffer_memory_end`两个变量是相等的，所以其实仅仅计算出了两个变量：`main_memory_start`, `memory_end`

就是一堆 `if else` 判断而已，判断的标准都是 `memory_end` 也就是内存最大值，这个内存最大值由第一行代码可以看出，是等于 `1M + 扩展内存大小`。就只是针对不同的内存大小，设置不同的边界值罢了。

那么如果内存为 8M 大小，`memory_end` 就是 `8 * 1024 * 1024`, 也就走倒数第二个分支，`buffer_memory_end` 就为 `2*1024*1024B=2MB`, 那么 `main_memory_start` 也为 `2*1024*1024B=2MB`

#figure(caption: [])[#image("images/chapter12-1.png", width: 40%)]

就是定了三个箭头所指向的地址的三个边界变量，具体主内存区是如何管理和分配的，要看下面代码

#figure(
```c
void main(void) {
    ...
    mem_init(main_memory_start, memory_end);
    ...
}
```,
caption: [main - mem_init]
)

而缓冲区是如何管理和分配的，要看

#figure(
```c
void main(void) {
    ...
    buffer_init(buffer_memory_end);
    ...
}
```,
caption: [main - buffer_init]
)

=== 进入 `mem_init`

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

就是给一个 `mem_map` 数组的各个位置上赋了值，这个数组的每个元素都代表一个 4K 内存的使用次数，而且起初全部赋值为 `USED` 也就是 `100`(使用了 `100` 次)，然后对其中一部分又赋值为了 `0` 表示未被使用(使用次数为`0`)。

就是准备了一个表，记录了哪些内存被占用了，哪些内存没被占用。仍然假设内存总共只有 8M。

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

实际上就是选择 `mem_map` 中首个空闲页面，并标记为已使用。

== `trap_init`: 键盘是什么时候生效的

计算机刚刚启动时，按键盘是无效的，但是过了一段时间后，再按下键盘就有效果了。到底过了多久之后，按下键盘才有效果呢？

按下键盘后会触发中断，CPU 收到键盘中断后，根据中断号，寻找由操作系统写好的键盘中断处理程序。这个中断处理程序会把键盘码放入一个队列中，由相应的用户程序或内核程序读取，并显示在控制台，或者其他用途，这就代表你的键盘生效了。

#figure(
```c
void main(void) {
    ...
    trap_init();
    ...
}

void trap_init(void) {
    int i;
    set_trap_gate(0,&divide_error);
    set_trap_gate(1,&debug);
    set_trap_gate(2,&nmi);
    set_system_gate(3,&int3);   /* int3-5 can be called from all */
    set_system_gate(4,&overflow);
    set_system_gate(5,&bounds);
    set_trap_gate(6,&invalid_op);
    set_trap_gate(7,&device_not_available);
    set_trap_gate(8,&double_fault);
    set_trap_gate(9,&coprocessor_segment_overrun);
    set_trap_gate(10,&invalid_TSS);
    set_trap_gate(11,&segment_not_present);
    set_trap_gate(12,&stack_segment);
    set_trap_gate(13,&general_protection);
    set_trap_gate(14,&page_fault);
    set_trap_gate(15,&reserved);
    set_trap_gate(16,&coprocessor_error);
    for (i=17;i<48;i++)
        set_trap_gate(i,&reserved);
    set_trap_gate(45,&irq13);
    set_trap_gate(39,&parallel_interrupt);
}
```,
caption: [trap_init]
)

简化一下`trap_init`

#figure(
```c
void trap_init(void) {
    int i;
    // set 了一堆 trap_gate
    set_trap_gate(0, &divide_error);
    ... 
    // 又 set 了一堆 system_gate
    set_system_gate(45, &bounds);
    ...
    // 又又批量 set 了一堆 trap_gate
    for (i=17;i<48;i++)
        set_trap_gate(i, &reserved);
    ...
}
```,
caption: [trap_init 简化版]
)

首先看 `set_trap_gate` 和 `set_system_gate`，最终的效果就是在中断描述符表中插入了一个中断描述符。这段代码就是往 `idt` 表里一项一项地写东西，其对应的中断号就是第一个参数，中断处理程序就是第二个参数。

#figure(
```c
#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \
    "movw %0,%%dx\n\t" \
    "movl %%eax,%1\n\t" \
    "movl %%edx,%2" \
    : \
    : "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \
    "o" (*((char *) (gate_addr))), \
    "o" (*(4+(char *) (gate_addr))), \
    "d" ((char *) (addr)),"a" (0x00080000))

#define set_trap_gate(n,addr) \
    _set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
    _set_gate(&idt[n],15,3,addr)
```,
caption: [`_set_gate`]
)

产生的效果就是，之后如果来一个中断后，CPU 根据其中断号，就可以到这个中断描述符表 `idt` 中找到对应的中断处理程序了。
 
#example("Example")[
```
set_trap_gate(0,&divide_error);
```
设置 0 号中断，对应的中断处理程序是 `divide_error`。等 CPU 执行除零指令的时候，会从硬件层面发起一个 0 号异常中断，然后执行由os定义的 `divide_error` ，执行完之后再返回。
]
 
#example("Example")[
```
set_system_gate(5,&overflow);
```
设置 5 号中断，对应的中断处理程序是 `overflow`，边界出错中断异常处理。
]
 

#tip("Tip")[
`trap` 与 `system` 的区别仅仅在于，设置的中断描述符的特权级不同，前者是 0（内核态），后者是 3（用户态）就理解为都是设置一个中断号和中断处理程序的对应关系就好了。
]

再往后，批量操作这里。17 到 48 号中断都批量设置为了 `reserved` 函数，这是保留的，后面各个硬件初始化时要重新设置好这些中断。

#figure(
```c
void trap_init(void) {
    ...
    for (i=17;i<48;i++)
        set_trap_gate(i,&reserved);
    ...
}
```,
caption: [trap_init - 批量操作]
)

所以整段代码执行下来，`idt` 表的内容会变成如下。
#figure(caption: [])[#image("images/chapter14-1.png", width: 60%)]

这行代码过去后，键盘依然不好使，键盘产生的中断的中断号是 `0x21`，此时这个中断号还仅仅对应着一个临时的中断处理程序 `&reserved`，接着往后看。

#figure(
```c
void main(void) {
    ...
    trap_init();
    ...
    tty_init();
    ...
}

void tty_init(void) {
    rs_init();
    con_init();
}

void con_init(void) {
    ...
    set_trap_gate(0x21,&keyboard_interrupt);
    ...
}
```,
caption: [tty_init]
)

注意到 `trap_init` 后有个 `tty_init`，最后根据调用链，会调用到一行添加 `0x21` 号中断处理程序的代码，就是刚刚的 `set_trap_gate`。而后面的 `keyboard_interrupt` 就是键盘的中断处理程序！从这一行代码开始，键盘就生效了！不过还有点小问题，现在的中断处于禁用状态，不论是键盘中断还是其他中断，通通都不好使。

而 `main` 方法继续往下读，还有一行`sti`，最终会对应一个同名的汇编指令 `sti`，表示允许中断。所以这行代码之后，键盘才真正开始生效！

#figure(
```c
void main(void) {
    ...
    trap_init();
    ...
    tty_init();
    ...
    sti();
    ...
}
```,
caption: [main - 允许中断]
)

== `blk_dev_init`: 读硬盘前的准备

读取硬盘需要有*块设备驱动程序*，而以文件的方式来读取则还有要再上面封装一层*文件系统*。把读出来的数据放到内存，还涉及到*内存中缓冲区的管理*。现在主要关注，读取块设备与内存缓冲区之间的桥梁，*块设备请求项的初始化工作*。

#figure(
```c
void main(void) {
    ...
    blk_dev_init();
    ...
}

void blk_dev_init(void) {
    int i;
    for (i=0; i<32; i++) {
        request[i].dev = -1;
        request[i].next = NULL;
    }
}
```,
caption: [blk_dev_init]
)

#figure(
```c
/*
 * Ok, this is an expanded form so that we can use the same
 * request for paging requests when that is implemented. In
 * paging, 'bh' is NULL, and 'waiting' is used to wait for
 * read/write completion.
 */
struct request {
    int dev;        /* -1 if no request */
    int cmd;        /* READ or WRITE */
    int errors;
    unsigned long sector;
    unsigned long nr_sectors;
    char * buffer;
    struct task_struct * waiting;
    struct buffer_head * bh;
    struct request * next;
};
```,
caption: [struct request]
)

这个结构就代表了一次读盘请求，其中：

- `dev` 表示设备号，`-1` 就表示空闲。
- `cmd` 表示命令，其实就是 `READ` 还是 `WRITE`，也就表示本次操作是读还是写。
- `errors` 表示操作时产生的错误次数。
- `sector` 表示起始扇区。
- `nr_sectors` 表示扇区数。
- `buffer` 表示数据缓冲区，也就是读盘之后的数据放在内存中的什么位置。
- `waiting` 是个 `task_struct` 结构，这可以表示一个进程，也就表示是哪个进程发起了这个请求。
- `bh` 是缓冲区头指针，这个后面讲完缓冲区就懂了，因为这个 `request` 是需要与缓冲区挂钩的。
- `next` 指向了下一个请求项。

#example("Example")[
比如读请求时，`cmd` 就是 `READ`，`sector` 和 `nr_sectors` 这俩就定位了所要读取的块设备的哪几个扇区，`buffer` 就定位了这些数据读完之后放在内存的什么位置。
]

这四个参数就能完整描述了一个读取硬盘的需求了。

#figure(caption: [读硬盘需求])[#image("images/chapter15-1.png", width: 30%)]

其他的参数，是为了更好地配合操作系统进行读写块设备操作，为了把多个读写块设备请求很好地组织起来。这个组织不但要有这个数据结构中 `hb` 和 `next` 等变量的配合，还要有后面的电梯调度算法的配合...

这个 `request` 结构可以完整描述一个读盘操作。然后那个 `request` 数组就是把它们都放在一起，并且它们又通过 `next` 指针串成链表。

#figure(caption: [request\[32\]])[#image("images/chapter15-2.png", width: 80%)]

后面读盘的全流程中，是怎么用到刚刚初始化的这个 `request[32]` 结构的。读操作的系统调用函数是 `sys_read`，简化一下，仅仅保留读取普通文件的分支

#figure(
```c
int sys_read(unsigned int fd,char * buf,int count) {
    struct file * file = current->filp[fd];
    struct m_inode * inode = file->f_inode;
    // 校验 buf 区域的内存限制
    verify_area(buf,count);
    // 仅关注目录文件或普通文件
    return file_read(inode,file,buf,count);
}
```,
caption: [sys_read 简化版]
)

入参 `fd` 是文件描述符，通过它可以找到一个文件的 `inode`，进而找到这个文件在硬盘中的位置。另两个入参 `buf` 就是要复制到的内存中的位置，`count` 就是要复制的字节数。

#figure(caption: [])[#image("images/chapter15-3.png", width: 65%)]

继续看`file_read` 函数。

#figure(
```c
int file_read(struct m_inode * inode, struct file * filp, char * buf, int count) {
    int left,chars,nr;
    struct buffer_head * bh;
    left = count;
    while (left) {
        if (nr = bmap(inode,(filp->f_pos)/BLOCK_SIZE)) {
            if (!(bh=bread(inode->i_dev,nr)))
                break;
        } else
            bh = NULL;
        nr = filp->f_pos % BLOCK_SIZE;
        chars = MIN( BLOCK_SIZE-nr , left );
        filp->f_pos += chars;
        left -= chars;
        if (bh) {
            char * p = nr + bh->b_data;
            while (chars-->0)
                put_fs_byte(*(p++),buf++);
            brelse(bh);
        } else {
            while (chars-->0)
                put_fs_byte(0,buf++);
        }
    }
    inode->i_atime = CURRENT_TIME;
    return (count-left)?(count-left):-ERROR;
}
```,
caption: [file_read]
)

就是一个 `while` 循环，每次读入一个块的数据，直到入参所要求的大小全部读完为止。直接看 `bread` 那一行。

#figure(
```c
int file_read(struct m_inode * inode, struct file * filp, char * buf, int count) {
    ...
    while (left) {
        ...
        if (!(bh=bread(inode->i_dev,nr)))
    }
}
```,
caption: [file_read - bread]
)

`bread` 就是去读某一个设备的某一个数据块号的内容。

#figure(
```c
struct buffer_head * bread(int dev,int block) {
    struct buffer_head * bh = getblk(dev,block);
    if (bh->b_uptodate)
        return bh;
    ll_rw_block(READ,bh);
    wait_on_buffer(bh);
    if (bh->b_uptodate)
        return bh;
    brelse(bh);
    return NULL;
}
```,
caption: [bread]
)

其中 `getblk` 先申请内存中的一个缓冲块，然后 `ll_rw_block` 负责把硬盘中数据读入这个缓冲块。

继续看`ll_rw_block`函数。

#figure(
```c
void ll_rw_block(int rw, struct buffer_head * bh) {
    ...
    make_request(major,rw,bh);
}

static void make_request(int major,int rw, struct buffer_head * bh) {
    ...
if (rw == READ)
        req = request+NR_REQUEST;
    else
        req = request+((NR_REQUEST*2)/3);
/* find an empty request */
    while (--req >= request)
        if (req->dev<0)
            break;
    ...
/* fill up the request-info, and add it to the queue */
    req->dev = bh->b_dev;
    req->cmd = rw;
    req->errors=0;
    req->sector = bh->b_blocknr<<1;
    req->nr_sectors = 2;
    req->buffer = bh->b_data;
    req->waiting = NULL;
    req->bh = bh;
    req->next = NULL;
    add_request(major+blk_dev,req);
}
```,
caption: [make_request]
)

#h(2em)具体说来，就是`ll_rw_block`会往刚刚的设备的请求项链表`request[32]`中添加一个请求项，只要`request[32]`中有未处理的请求项，都会陆续处理，直到设备的请求项链表是空为止。

具体怎么读盘，就是与硬盘 IO 端口进行交互的过程了，可以继续往里跟，直到看到一个 `hd_out` 函数为止，这里姑且不展开。

在 `main` 函数的 `init` 系列函数中，通过 `blk_dev_init` 为后面的块设备访问，提前建立了一个数据结构，作为访问块设备和内存缓冲区之间的桥梁。

== `tty_init`: 键盘输入到显示器输出字符

#figure(
```c
void tty_init(void)
{
    rs_init();
    con_init();
}
void rs_init(void)
{
    set_intr_gate(0x24,rs1_interrupt);
    set_intr_gate(0x23,rs2_interrupt);
    init(tty_table[1].read_q.data);
    init(tty_table[2].read_q.data);
    outb(inb_p(0x21)&0xE7,0x21);
}
void con_init(void) {
    ...
    if (ORIG_VIDEO_MODE == 7) {
        ...
        if ((ORIG_VIDEO_EGA_BX & 0xff) != 0x10) {...}
        else {...}
    } else {
        ...
        if ((ORIG_VIDEO_EGA_BX & 0xff) != 0x10) {...}
        else {...}
    }
    ...
}
```,
caption: [tty_init]
)

- `rs_init`是串口中断的开启，以及设置对应的中断处理程序。
- `con_init`根据不同的显示模式有不同的`if else`，来分配不同的变量值，那如果仅以一个显示模式为例，这些分支就可以只看一个了。
 
#definition("Definition")[
*显示模式*：规定一个字符是如何显示在屏幕上的。例如，如果可以随意操作内存和 CPU 等设备，如何操作能使显示器上显示一个字符`'a'`？
]

内存中有这样一部分区域，是和显存映射的。就是往下图的内存区域中写数据，相当于写在了显存中。而往显存中写数据，就相当于在屏幕上输出文本了。
#figure(caption: [])[#image("images/chapter16-1.png", width: 50%)]

#example("Example")[
如果写这一行汇编语句。

```
mov [0xB8000],'h'
```

后面 `'h'` 汇编编辑器会转换成 ASCII 码的二进制数值，也可以直接写。

```
mov [0xB8000],0x68
```

其实就是往内存中 `0xB8000` 这个位置写了一个值，只要一写，屏幕上就会是这样。
#figure(caption: [])[#image("images/chapter16-2.png", width: 60%)]
]

具体说来，这块内存区域是每两个字节表示一个显示在屏幕上的字符，第一个是字符的编码，第二个是字符的颜色，姑且先不管颜色，如果多写几个字符。

```
mov [0xB8000],'h'
mov [0xB8002],'e'
mov [0xB8004],'l'
mov [0xB8006],'l'
mov [0xB8008],'o'
```

此时屏幕：
#figure(caption: [])[#image("images/chapter16-4.png", width: 60%)]

回看刚刚的代码，假设显示模式是现在的这种文本模式，条件分支就可以去掉好多。代码可以简化成这个样子。

#figure(
```c
#define ORIG_X          (*(unsigned char *)0x90000)
#define ORIG_Y          (*(unsigned char *)0x90001)
void con_init(void) {
    register unsigned char a;
    // 第一部分 获取显示模式相关信息
    video_num_columns = (((*(unsigned short *)0x90006) & 0xff00) >> 8);
    video_size_row = video_num_columns * 2;
    video_num_lines = 25;
    video_page = (*(unsigned short *)0x90004);
    video_erase_char = 0x0720;
    // 第二部分 显存映射的内存区域 
    video_mem_start = 0xb8000;
    video_port_reg  = 0x3d4;
    video_port_val  = 0x3d5;
    video_mem_end = 0xba000;
    // 第三部分 滚动屏幕操作时的信息
    origin  = video_mem_start;
    scr_end = video_mem_start + video_num_lines * video_size_row;
    top = 0;
    bottom  = video_num_lines;
    // 第四部分 定位光标并开启键盘中断
    gotoxy(ORIG_X, ORIG_Y);
    set_trap_gate(0x21,&keyboard_interrupt);
    outb_p(inb_p(0x21)&0xfd,0x21);
    a=inb_p(0x61);
    outb_p(a|0x80,0x61);
    outb(a,0x61);
}
```,
caption: [con_init]
)

#tip("Tip")[
    回忆之前`setup.s`存储的设备信息：
#align(center,
  three-line-table[
  |内存地址|长度(字节)|名称|
  |-|-|-|
  |0x90000       |2  |光标位置|
  |0x90002       |2  |扩展内存数|
  |0x90004       |2  |显示页面|
  |0x90006       |1  |显示模式|
  |0x90007       |1  |字符列数|
  |0x90008       |2  |未知|
  |0x9000A       |1  |显示内存|
  |0x9000B       |1  |显示状态|
  |0x9000C       |2  |显卡特性参数|
  |0x9000E       |1  |屏幕行数|
  |0x9000F       |1  |屏幕列数|
  |0x90080       |16 |硬盘1参数表|
  |0x90090       |16 |硬盘2参数表|
  |0x901FC       |2  |根设备号|
  ]
)

]

- 第一部分获取 `0x90006` 地址处的数据，就是获取显示模式等相关信息。
- 第二部分就是显存映射的内存地址范围，现在假设是 CGA 类型的文本模式，所以映射的内存是从 `0xB8000` 到 `0xBA000`。
- 第三部分是设置一些滚动屏幕时需要的参数，定义顶行和底行是哪里，这里顶行就是第一行，底行就是最后一行，很合理。
- 第四部分是把光标定位到之前保存的光标位置处（取内存地址 `0x90000` 处的数据），然后设置并开启键盘中断。开启键盘中断后，键盘上敲击一个按键后就会触发中断，中断程序就会读键盘码转换成 ASCII 码，然后写到光标处的内存地址，也就相当于往显存写，于是这个键盘敲击的字符就显示在了屏幕上。

目前可以实现

1. 根据已有信息已经可以实现往屏幕上的任意位置写字符，还能指定颜色。
2. 接受键盘中断，根据键盘码中断处理程序就可以得知哪个键按下了。

一切的起点，就是第四步的 `gotoxy` 函数，定位当前光标。

#figure(
```c
#define ORIG_X          (*(unsigned char *)0x90000)
#define ORIG_Y          (*(unsigned char *)0x90001)
void con_init(void) {
    ...
    // 第四部分 定位光标并开启键盘中断
    gotoxy(ORIG_X, ORIG_Y);
    ...
}
static inline void gotoxy(unsigned int new_x, unsigned int new_y) {
   ...
   x = new_x; // 光标所在列
   y = new_y; // 光标所在行
   // pos 即根据x和y计算出来的内存指针
   // 往pos处写数据相当于往控制台的(x, y)处写入字符了
   pos = origin + y*video_size_row + (x<<1);
}
```,
caption: [gotoxy]
)

按下键盘后，触发键盘中断，之后的程序调用链是这样的。

#figure(
```c
_keyboard_interrupt:
    ...
    call _do_tty_interrupt
    ...
void do_tty_interrupt(int tty) {
   copy_to_cooked(tty_table+tty);
}

void copy_to_cooked(struct tty_struct * tty) {
    ...
    tty->write(tty);
    ...
}
// 控制台时 tty 的 write 为 con_write 函数
void con_write(struct tty_struct * tty) {
    ...
    __asm__("movb _attr,%%ah\n\t"
      "movw %%ax,%1\n\t"
      ::"a" (c),"m" (*(short *)pos)
      :"ax");
     pos += 2;
     x++;
    ...
}
```,
caption: [键盘终端调用链]
)

看最后一个函数 `con_write` 中的关键代码。`__asm__` 内联汇编，就是把键盘输入的字符 `c` 写入 `pos` 指针指向的内存，相当于往屏幕输出了。之后两行 `pos+=2` 和 `x++`，就是调整所谓的光标。

写入一个字符，其实就是往内存的某处写个数据，然后顺便调整一下光标。由此也可以看出，光标的本质，其实就是这里的 `x`, `y`, `pos` 这仨变量而已。

还可以做换行效果，当发现光标位置处于某一行的结尾时（都知道屏幕上一共有几行几列了），就把光标计算出一个新值，让其处于下一行的开头。就一个计算公式即可搞定，在 `con_write` 源码处仍有体现，即判断列号 `x` 是否大于了总列数。

#figure(
```c
void con_write(struct tty_struct * tty) {
    ...
    if (x>=video_num_columns) {
        x -= video_num_columns;
        pos -= video_size_row;
        lf();
  }
  ...
}

static void lf(void) {
   if (y+1<bottom) {
      y++;
      pos += video_size_row;
      return;
   }
 ...
}
```,
caption: [控制台换行]
)

类似的，还可以实现滚屏，无非就是当检测到光标已经出现在最后一行最后一列了，那就把每一行的字符，都复制到它上一行，其实就是算好哪些内存地址上的值，拷贝到哪些内存地址，就好了。(源码位于`/kernel/chr_drv/console.c`)
 
有了这个初始化工作，就可以利用这些信息，弄几个算法，实现各种常见控制台的操作。

所以 `console.c` 中的其他方法就是做这个事的，就不展开每一个方法了，简单看看有哪些方法。

#figure(
```c
// 定位光标的
static inline void gotoxy(unsigned int new_x, unsigned int new_y){}
// 滚屏，即内容向上滚动一行
static void scrup(void){}
// 光标同列位置下移一行
static void lf(int currcons){}
// 光标回到第一列
static void cr(void){}
...
// 删除一行
static void delete_line(void){}
```,
caption: [console.c]
)

`console.c` 是整个内核中代码量最大的文件，但功能特别单一，也都很简单，主要是处理键盘各种不同的按键，需要写好多 switch case 等语句，没必要去展开。
 
到这里 `tty_init` 的工作就完成了。此后，kernel就可以用它来方便地在控制台输出字符了。想要在启动过程中告诉用户一些信息，以及后面内核完全建立起来之后，由用户用 shell 进行操作时手动输入命令，都是可以用到这里的代码的！
== `time_init`: 获取时间

继续看下一个初始化`time_init`

#figure(
```c
#define CMOS_READ(addr) ({ \
    outb_p(0x80|addr,0x70); \
    inb_p(0x71); \
})

#define BCD_TO_BIN(val) ((val)=((val)&15) + ((val)>>4)*10)

static void time_init(void) {
    struct tm time;
    do {
        time.tm_sec = CMOS_READ(0);
        time.tm_min = CMOS_READ(2);
        time.tm_hour = CMOS_READ(4);
        time.tm_mday = CMOS_READ(7);
        time.tm_mon = CMOS_READ(8);
        time.tm_year = CMOS_READ(9);
    } while (time.tm_sec != CMOS_READ(0));
    BCD_TO_BIN(time.tm_sec);
    BCD_TO_BIN(time.tm_min);
    BCD_TO_BIN(time.tm_hour);
    BCD_TO_BIN(time.tm_mday);
    BCD_TO_BIN(time.tm_mon);
    BCD_TO_BIN(time.tm_year);
    time.tm_mon--;
    startup_time = kernel_mktime(&time);
}
```,
caption: [time_init]
)

主要就是 `CMOS_READ` 和 `BCD_TO_BIN`。
 
首先是 `CMOS_READ`

#figure(
```c
#define CMOS_READ(addr) ({ \
    outb_p(0x80|addr,0x70); \
    inb_p(0x71); \
})
```,
caption: [CMOS_READ]
)

就是对一个端口先 `out` 写一下，再 `in` 读一下。

CPU 与外设打交道基本是通过端口，往某些端口写值来表示要这个外设干嘛，然后从另一些端口读值来接受外设的反馈。至于这个外设内部是怎么实现的，os无需关心。

`CMOS` 这个外设比较陌生，这里以与硬盘的交互为例。最常见的就是读硬盘了，硬盘的端口表。

#align(center,
three-line-table[
|端口  |读                              |写|
| -    | -                              |-|
|0x1F0 |数据寄存器	                |数据寄存器|
|0x1F1 |错误寄存器	                |特征寄存器|
|0x1F2 |扇区计数寄存器	                |扇区计数寄存器|
|0x1F3 |扇区号寄存器或 LBA 块地址 0~7	|扇区号或 LBA 块地址 0~7|
|0x1F4 |磁道数低 8 位或 LBA 块地址 8~15	|磁道数低 8 位或 LBA 块地址 8~15|
|0x1F5 |磁道数高 8 位或 LBA 块地址 16~23|磁道数高 8 位或 LBA 块地址 16~23|
|0x1F6 |驱动器/磁头或 LBA 块地址 24~27	|驱动器/磁头或 LBA 块地址 24~27|
|0x1F7 |命令寄存器或状态寄存器	        |命令寄存器|
]
)

读硬盘即，往除了第一个以外的后面几个端口写数据，告诉要读硬盘的扇区号，字节数。然后再从 `0x1F0` 端口读数据。
    1. 在 `0x1F2` 写入要读取的扇区数
    2. 在 `0x1F3` ~ `0x1F6` 这四个端口写入计算好的起始 LBA 地址
    3. 在 `0x1F7` 处写入读命令的指令号
    4. 不断检测 `0x1F7` （此时已成为状态寄存器的含义）的忙位
    5. 如果第四步骤为不忙，则开始不断从 `0x1F0` 处读取数据到内存指定位置，直到读完
 
读取硬盘的这个轮询操作会占用 CPU 的计算资源，可以交给 DMA 设备，但和硬盘的交互，都是按照硬件手册上的端口说明，来操作的。
 
回到`CMOS`，它是主板上的一个可读写的 RAM 芯片，开机时长按某个键就可以进入设置它的页面。

#figure(caption: [])[#image("images/chapter17-1.png", width: 70%)]

`time_init`就是与它打交道，获取它的一些数据。

#figure(
```c
static void time_init(void) {
    struct tm time;
    do {
        time.tm_sec = CMOS_READ(0);
        time.tm_min = CMOS_READ(2);
        time.tm_hour = CMOS_READ(4);
        time.tm_mday = CMOS_READ(7);
        time.tm_mon = CMOS_READ(8);
        time.tm_year = CMOS_READ(9);
    } while (time.tm_sec != CMOS_READ(0));
    BCD_TO_BIN(time.tm_sec);
    BCD_TO_BIN(time.tm_min);
    BCD_TO_BIN(time.tm_hour);
    BCD_TO_BIN(time.tm_mday);
    BCD_TO_BIN(time.tm_mon);
    BCD_TO_BIN(time.tm_year);
    time.tm_mon--;
    startup_time = kernel_mktime(&time);
}
```,
caption: [time_init]
)

前面几个赋值语句 `CMOS_READ` 就是通过读写 `CMOS` 上的指定端口，依次获取年月日时分秒等信息。至于 `CMOS` 又是如何知道时间的，这个就不在讨论范围了。
 
接下来 `BCD_TO_BIN` 就是 `BCD` 转换成 `BIN`，因为从 `CMOS` 上获取的这些年月日都是 `BCD` 码值，需要转换成存储在变量上的二进制数值。
 
最后一步 `kernel_mktime` 就是根据刚刚的那些时分秒数据，计算从 1970 年 1 月 1 日 0 时起到开机当时经过的秒数，作为开机时间，存储在 `startup_time`。

#figure(
```c
startup_time = kernel_mktime(&time);

// kernel/mktime.c
long kernel_mktime(struct tm * tm)
{
    long res;
    int year;
    year = tm->tm_year - 70;
    res = YEAR*year + DAY*((year+1)/4);
    res += month[tm->tm_mon];
    if (tm->tm_mon>1 && ((year+2)%4))
        res -= DAY;
    res += DAY*(tm->tm_mday-1);
    res += HOUR*tm->tm_hour;
    res += MINUTE*tm->tm_min;
    res += tm->tm_sec;
    return res;
}
```,
caption: [kernel_mktime]
)
== `sched_init`: 进程调度

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

#figure(caption: [])[#image("images/chapter18-1.png",width: 60%)]

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
caption: [struct tss_struct]
)
]

#definition("Definition")[
`LDT` 叫局部描述符表，与 `GDT` 全局描述符表相对应的，内核态的代码用 `GDT` 里的数据段和代码段，用户进程的代码用每个用户进程自己的 `LDT` 里的数据段和代码段。
]

#figure(caption: [])[#image("images/chapter18-2.png", width: 60%)]

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
  #figure(caption: [])[#image("images/chapter18-4.png", width: 60%)]
  以后每创建一个新进程，就会在后面添加一组 `TSS` 和 `LDT` 表示这个进程的任务状态段以及局部描述符表信息。

#tip("Tip")[
现在还没有建立起进程调度的机制，但正在运行的代码会作为未来的一个进程的指令流。也就是当未来进程调度机制一建立起来，正在执行的代码就会化身成为进程 0 的代码。所以需要提前把这些未来会作为进程 0 的信息写好。因此一开始就先有了一组 `TSS` 和 `LDT`。
]

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
- `lidt` 指令：给 `idtr` 寄存器赋值，告诉 CPU 中断描述符表 `idt` 在内存的位置。
- `lgdt` 指令：给 `gdtr` 寄存器赋值，告诉 CPU 全局描述符表 `gdt` 在内存的位置。
]

这里，`ltr` 是给 `tr` 寄存器赋值，以告诉 CPU 任务状态段 `TSS` 在内存的位置；`lldt` 一个是给 `ldt` 寄存器赋值，以告诉 CPU 局部描述符 `LDT` 在内存的位置。CPU 之后就能通过 `tr` 寄存器找到当前进程的任务状态段信息，也就是上下文信息，以及通过 `ldt` 寄存器找到当前进程在用的局部描述符表信息。

#figure(caption: [])[#image("images/chapter18-5.png", width:55%)]

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
  - 第二个设置的中断叫系统调用 `system_call`，中断号是`0x80`，所有用户态程序想要调用内核提供的方法，都需要基于这个系统调用来进行。

#tip("目前已经设置好的中断: ")[
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
]

== `buffer_init`: 缓冲区

#figure(
```c
void main(void) {
    ...
    mem_init(main_memory_start,memory_end);
    trap_init();
    blk_dev_init();
    chr_dev_init();
    tty_init();
    time_init();
    sched_init();
    buffer_init(buffer_memory_end);
    ...
}
```,
caption: [main - buffer_init]
)

这个函数传了 `buffer_memory_end`，这个是在`mem_init`就设置好的。依然假设内存 8M，把一些不相干的分支去掉。

#figure(
```c
extern int end;
struct buffer_head * start_buffer = (struct buffer_head *) &end;

void buffer_init(long buffer_end) {
    struct buffer_head * h = start_buffer;
    void * b = (void *) buffer_end;
    while ( (b -= 1024) >= ((void *) (h+1)) ) {
        h->b_dev = 0;
        h->b_dirt = 0;
        h->b_count = 0;
        h->b_lock = 0;
        h->b_uptodate = 0;
        h->b_wait = NULL;
        h->b_next = NULL;
        h->b_prev = NULL;
        h->b_data = (char *) b;
        h->b_prev_free = h-1;
        h->b_next_free = h+1;
        h++;
    }
    h--;
    free_list = start_buffer;
    free_list->b_prev_free = h;
    h->b_next_free = free_list;
    for (int i=0;i<307;i++)
        hash_table[i]=NULL;
}
```,
caption: [buffer_init - 简化版]
)

=== 链接器计算好的`end`

#figure(
```c
extern int end;
void buffer_init(long buffer_end) {
    struct buffer_head * start_buffer = (struct buffer_head *) &end;
    ...
}
```,
caption: [buffer_init - part1]
)

这里有个外部变量`end`(内核程序和缓冲区的分界)，而缓冲区开始位置 `start_buffer` 就等于这个变量的内存地址。这个外部变量`end` 并不是内核写好的，而是由链接器 `ld` 在链接整个程序时设置的一个外部变量，计算好了整个内核代码的末尾地址。那在这之前的是内核代码区域肯定不能用，在这之后的，就给 `buffer` 用了。所以内存分布图可以更精确一点了。

#figure(caption: [])[#image("images/chapter19-1.png", width: 55%)]

主内存和缓冲区的分界线，就直接代码里写死了，就是上图中的 2M。而kernel占多大内存在写的时候完全不知道，就算知道了如果改动一点代码也会变化，所以就由链接器把这个内核代码末端的地址计算出来，作为一个外部变量 `end`。

=== 缓冲区的数据结构
#figure(
```c
void buffer_init(long buffer_end) {
    ...
    void * b = (void *) buffer_end;
    while ( (b -= 1024) >= ((void *) (h+1)) ) {
        ...
        h->b_data = (char *) b;
        h->b_prev_free = h-1;
        h->b_next_free = h+1;
        h++;
    }
    ...
}
```,
caption: [buffer_init - part2]
)

定义了两个变量
- 一个是 `buffer_head` 结构的 `h`，代表缓冲头，其指针值是 `start_buffer`，刚刚计算过，就是图中的内核代码末端地址 `end`，也就是缓冲区开头。
- 一个是 `b`，代表缓冲块，指针值是 `buffer_end`，也就是图中的 2M，就是缓冲区结尾。

缓冲区结尾的 `b` 每次循环 `-1024`，也就是一个缓冲块的值，缓冲区结尾的 `h` 每次循环 `+1`（一个 `buffer_head` 大小的内存），直到碰一块为止。

#figure(caption: [])[#image("images/chapter19-2.png", width: 40%)]

这个 `b` 就代表缓冲块，`h` 代表缓冲头，一个从上往下，一个从下往上。`h` 被附上了属性值，其中比较关键的是这个 `buffer` 所表示的数据部分 `b_data`，也就是指向了上面的缓冲块 `b`。还有这个 `buffer` 的前后空闲 `buffer` 的指针 `b_prev_free` 和 `b_next_free`。

#figure(caption: [])[#image("images/chapter19-3.png", width: 50%)]

当缓冲头 `h` 的所有 `next` 和 `prev` 指针都指向彼此时，就构成了一个双向链表。

#figure(
```c
void buffer_init(long buffer_end) {
    ...
    free_list = start_buffer;
    free_list->b_prev_free = h;
    h->b_next_free = free_list;
    ...
}
```,
caption: [buffer_init - part3]
)

#figure(caption: [])[#image("images/chapter19-4.png", width: 45%)]

`free_list` 指向了缓冲头双向链表的第一个第一个缓冲头，然后就可以顺着这个结构从双向链表中遍历到任何一个缓冲头了，而通过缓冲头又可以找到这个缓冲头对应的缓冲块。

=== `hash_table`

#figure(
```c
void buffer_init(long buffer_end) {
    ...
    for (i=0;i<307;i++)
        hash_table[i]=NULL;
}
```,
caption: [buffer_init - part4]
)

一个 307 大小的 `hash_table` 数组，这个代码在 `buffer.c` 中，而 `buffer.c` 是在`fs` 之下的。它今后是为文件系统服务的，具体是内核程序如果需要访问块设备中的数据，就都需要经过缓冲区来间接地操作。也就是说，读取块设备的数据（硬盘中的数据），需要先读到缓冲区中，如果缓冲区已有了，就不用从块设备读取了，直接取走。

那怎么知道缓冲区已经有了要读取的块设备中的数据呢？双向链表从头遍历当然可以，但这效率太低了。所以需要一个 `hashmap` 的结构方便快速查找。之后当要读取某个块设备上的数据时，首先要搜索相应的缓冲块，是下面这个函数。

#figure(
```c
#define _hashfn(dev,block) (((unsigned)(dev^block))%307)
#define hash(dev,block) hash_table[_hashfn(dev,block)]

// 搜索合适的缓冲块
struct buffer_head * getblk(int dev,int block) {
    ...
    struct buffer_head bh = get_hash_table(dev,block);
    ...
}

struct buffer_head * get_hash_table(int dev, int block) {
    ...
    find_buffer(dev,block);
    ...
}

static struct buffer_head * find_buffer(int dev, int block) {
    ...
    hash(dev,block);
    ...
}
```,
caption: [hash_table]
)

一路跟下来发现，就是通过 `dev^block % 307` 即 `(设备号^逻辑块号) Mod 307`。找到在 `hash_table` 里的索引下标，如果冲突就形成链表。

#figure(caption: [])[#image("images/chapter19-5.png", width: 65%)]

哈希表 + 双向链表，很容易想到这可以实现 LRU 算法，之后的缓冲区使用和弃用，正是这个算法。之后在讲通过文件系统来读取硬盘文件时，都需要使用和弃用这个缓冲区里的内容，缓冲区即是用户进程的内存和硬盘之间的桥梁。

== `hd_init`: 硬盘

#figure(
```c
//struct blk_dev_struct {
//    void (*request_fn)(void);
//    struct request * current_request;
//};
//extern struct blk_dev_struct blk_dev[NR_BLK_DEV];

void hd_init(void) {
    blk_dev[3].request_fn = do_hd_request;
    set_intr_gate(0x2E,&hd_interrupt);
    outb_p(inb_p(0x21)&0xfb,0x21);
    outb(inb_p(0xA1)&0xbf,0xA1); 
}
```,
caption: [hd_init]
)

一共就四行代码。硬件设备的初始通常都比较简单，大体都是：

1. 往某些 IO 端口上读写一些数据，表示开启它；
2. 然后再向中断向量表中添加一个中断，使得 CPU 能够响应这个硬件设备的动作；
3. 最后再初始化一些数据结构来管理。不过内存管理之类的结构可能复杂些，外设的管理，相对就简单很多。

=== `do_hd_request`

看第一行代码：

#figure(
```c
void hd_init(void) {
    blk_dev[3].request_fn = do_hd_request;
    ...
}
```,
caption: [hd_init - part1]
)

把 `blk_dev` 数组索引 `3` 位置处的块设备管理结构 `blk_dev_struct` 的 `request_fn` 赋值为了 `do_hd_request`：

因为有很多块设备，所以 Linux 0.11 用了一个 `blk_dev[]` 来进行管理，每一个索引表示一个块设备。`blk_dev[3]`就是给硬盘留的位置。

#figure(
```c
struct blk_dev_struct blk_dev[NR_BLK_DEV] = {
    { NULL, NULL },     /* no_dev */
    { NULL, NULL },     /* dev mem */
    { NULL, NULL },     /* dev fd */
    { NULL, NULL },     /* dev hd */
    { NULL, NULL },     /* dev ttyx */
    { NULL, NULL },     /* dev tty */
    { NULL, NULL }      /* dev lp */
};
```,
caption: [blk_dev]
)

那么每个块设备执行读写请求都有自己的函数实现，在上层看来都是一个统一函数 `request_fn` 即可，具体实现各有不同，对于硬盘来说，这个实现就是 `do_hd_request` 函数。

#tip("Tip")[
有点像接口？这就是多态在 C 语言的体现, 用 Java 程序员熟悉的话就是，父类引用 `request_fn` 指向子类对象 `do_hd_request` 的感觉。
]

=== 设置`hd_interrupt`中断

再看第二行。

#figure(
```c
void hd_init(void) {
    ...
    set_intr_gate(0x2E,&hd_interrupt);
    ...
}
```,
caption: [hd_init - part2]
)

这里就是又设置了一个新的中断，中断号是 `0x2E`，中断处理函数是 `hd_interrupt`，也就是说硬盘发生读写时，硬盘会发出中断信号给 CPU，之后 CPU 便会陷入中断处理程序，也就是执行 `hd_interrupt` 函数。

#figure(
```c
_hd_interrupt:
    ...
    xchgl _do_hd,%edx
    ...

// 如果是读盘操作，这个 do_hd 是 read_intr
static void read_intr(void) {
    ...
    do_hd_request();
    ...
}
```,
caption: [hd_interrupt]
)

#tip("此时的中断向量表")[
  #align(center, 
    three-line-table[
    |中断号   | 中断处理函数|
    | -       | - |
    |0 ~ 0x10 | trap_init 里设置的一堆(除零异常...)|
    |0x20     |timer_interrupt|
    |0x21     |keyboard_interrupt|
    |0x2E     |hd_interrupt|
    |0x80     |system_call|
    ]
  )
]

#tip("Tip")[
操作系统就是一个靠中断驱动的死循环而已，如果不发生任何中断，操作系统会一直在一个死循环里等待。换句话说，让操作系统工作的唯一方式，就是触发中断。
]

=== 发送中断请求信号

再往下看后两行。

#figure(
```c
void hd_init(void) {
    ...
    outb_p(inb_p(0x21)&0xfb,0x21);
    outb(inb_p(0xA1)&0xbf,0xA1); 
}
```,
caption: [hd_init - part3]
)
就是往几个 IO 端口上读写，其作用是允许硬盘控制器发送中断请求信号。

#pagebreak()
