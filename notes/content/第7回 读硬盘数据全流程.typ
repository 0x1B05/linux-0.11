#import "../template.typ":*

= 读硬盘数据全流程

== `sys_read`: 将数据从硬盘加载到内存

通过加载根文件系统和打开文件的操作，已经可以方便地通过一个文件描述符 `fd`，寻找到存储在硬盘中的一个文件了，就是知道这个文件在硬盘中的哪几个扇区中。

#figure(
```c
// 把这个fd指向的硬盘中的文件，复制count字节到内存中的buf。
int sys_read(unsigned int fd,char * buf,int count) {
    ...
}
```,
caption: [sys_read]
)

这就是 Linux 0.11 读操作的系统调用入口函数，在 `read_write.c` 这个文件里。

#figure(
```c
// read_write.c
int sys_read(unsigned int fd,char * buf,int count) {
    struct file * file;
    struct m_inode * inode;

    if (fd>=NR_OPEN || count<0 || !(file=current->filp[fd]))
        return -EINVAL;
    if (!count)
        return 0;
    verify_area(buf,count);
    inode = file->f_inode;
    if (inode->i_pipe)
        return (file->f_mode&1)?read_pipe(inode,buf,count):-EIO;
    if (S_ISCHR(inode->i_mode))
        return rw_char(READ,inode->i_zone[0],buf,count,&file->f_pos);
    if (S_ISBLK(inode->i_mode))
        return block_read(inode->i_zone[0],&file->f_pos,buf,count);
    if (S_ISDIR(inode->i_mode) || S_ISREG(inode->i_mode)) {
        if (count+file->f_pos > inode->i_size)
            count = inode->i_size - file->f_pos;
        if (count<=0)
            return 0;
        return file_read(inode,file,buf,count);
    }
    printk("(Read)inode->i_mode=%06o\n\r",inode->i_mode);
    return -EINVAL;
}
```,
caption: [sys_read - linux0.11]
)

先简化一下，去掉一些错误校验逻辑等旁路分支，并添加上注释。

#figure(
```c
// read_write.c
int sys_read(unsigned int fd,char * buf,int count) {
    struct file * file = current->filp[fd];
    // 校验 buf 区域的内存限制
    verify_area(buf,count);
    struct m_inode * inode = file->f_inode;
    // 管道文件
    if (inode->i_pipe)
        return (file->f_mode&1)?read_pipe(inode,buf,count):-EIO;
    // 字符设备文件
    if (S_ISCHR(inode->i_mode))
        return rw_char(READ,inode->i_zone[0],buf,count,&file->f_pos);
    // 块设备文件
    if (S_ISBLK(inode->i_mode))
        return block_read(inode->i_zone[0],&file->f_pos,buf,count);
    // 目录文件或普通文件
    if (S_ISDIR(inode->i_mode) || S_ISREG(inode->i_mode)) {
        if (count+file->f_pos > inode->i_size)
            count = inode->i_size - file->f_pos;
        if (count<=0)
            return 0;
        return file_read(inode,file,buf,count);
    }
    // 不是以上几种，就报错
    printk("(Read)inode->i_mode=%06o\n\r",inode->i_mode);
    return -EINVAL;
}
```,
caption: [sys_read - 简化版]
)

这个函数将管道文件、字符设备文件、块设备文件、目录文件、普通文件分别指向了不同的具体实现。这里姑且仅仅关注最常用的，读取目录文件或普通文件，并且不考虑读取的字节数大于文件本身大小这种不合理情况，再简化下代码。

#figure(
```c
// read_write.c
int sys_read(unsigned int fd,char * buf,int count) {
    struct file * file = current->filp[fd];
    struct m_inode * inode = file->f_inode;
    // 校验 buf 区域的内存限制
    verify_area(buf,count);
    // 仅关注目录文件或普通文件
    return file_read(inode,file,buf,count);
}
```,
caption: [sys_read - 再简化版]
)

- 第一步，根据文件描述符 `fd`，在进程表里拿到了 `file` 信息，进而拿到了 `inode` 信息。
- 第二步，对 `buf` 区域的内存做校验。
- 第三步，调用具体的 `file_read` 函数进行读操作。

在进程表 `filp` 中拿到 `file` 信息进而拿到 `inode` 信息这一步就是在打开一个文件时，或者像管道文件一样创建出一个管道文件时，就封装好了 `file` 以及它的 `inode` 信息。

== 对 `buf` 区域的内存做校验 `verify_area`

#figure(
```c
// fork.c
void verify_area(void * addr,int size) {
    unsigned long start;
    start = (unsigned long) addr;
    size += start & 0xfff;
    start &= 0xfffff000;
    start += get_base(current->ldt[2]);
    while (size>0) {
        size -= 4096;
        write_verify(start);
        start += 4096;
    }
}
```,
caption: [verify_area]
)

`addr` 就是刚刚的 `buf`，`size` 就是刚刚的 `count`。然后这里又将 `addr` 赋值给了 `start` 变量。所以代码开始，`start` 就表示要复制到的内存的起始地址，`size` 就是要复制的字节数。

这里需要回顾Linux 0.11里内存的分段和分页机制。

Linux 0.11 对内存是以 4K 为一页单位来划分内存的，所以内存看起来就是一个个 4K 的小格子。
#figure(caption: [])[#image("images/chapter40-1.png", width: 30%)]

假设要复制到的内存的起始地址 `start` 和要复制的字节数 `size` 在图中的那个位置。那么开始的两行计算代码。

#figure(
```c
// fork.c
void verify_area(void * addr,int size) {
    ...
    // 将start和size按页对齐。
    size += start & 0xfff;
    start &= 0xfffff000;
    // 再加上每个进程的不同数据段基址
    // 具体说来就是加上当前进程 LDT 中的数据段的段基址
    start += get_base(current->ldt[2]);
    ...
}
```,
caption: [verify_area - part1]
)

#figure(caption: [])[#image("images/chapter40-2.png", width: 60%)]

每个进程的 `LDT` 表，由 Linux 创建进程时的代码给规划好了。具体说来，就是如上图所示，每个进程的线性地址范围，是 `(进程号)*64M ~  (进程号+1)*64M`

而对于进程本身来说，都以为自己是从零号地址开始往后的 64M，所以传入的 `start` 值也是以零号地址为起始地址算出来的。但现在经过系统调用进入 `sys_write` 后会切换为内核态，内核态访问数据会通过基地址为 0 的全局描述符表中的数据段来访问数据。所以，`start` 要加上它自己进程的数据段基址。

再之后，就是对这些页进行具体的验证操作。

#figure(
```c
// fork.c
void verify_area(void * addr,int size) {
    ...
    while (size>0) {
        size -= 4096;
        write_verify(start);
        start += 4096;
    }
}
```,
caption: [verify_area - part2]
)

#figure(caption: [])[#image("images/chapter40-3.png", width: 50%)]

这些 `write_verify` 将会对这些页进行写页面验证，如果页面存在但不可写，则执行 `un_wp_page` 复制页面(取消页面的写保护，即写时复制的原理)。

#figure(
```c
// memory.c
void write_verify(unsigned long address) {
    unsigned long page;
    if (!( (page = *((unsigned long *) ((address>>20) & 0xffc)) )&1))
        return;
    page &= 0xfffff000;
    page += ((address>>10) & 0xffc);
    if ((3 & *(unsigned long *) page) == 1)  /* non-writeable, present */
        un_wp_page((unsigned long *) page);
    return;
}
```,
caption: [write_verify]
)

== 执行`file_read`读操作

页校验完之后，就调用 `file_read` 函数。

#figure(
```c
// read_write.c
int sys_read(unsigned int fd,char * buf,int count) {
    ...
    return file_read(inode,file,buf,count);
}

// file_dev.c
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

就是一个 `while` 循环，每次读入一个块的数据，直到入参所要求的大小全部读完为止。 `while` 去掉，简化一下。

#figure(
```c
// file_dev.c
int file_read(struct m_inode * inode, struct file * filp, char * buf, int count) {
    ...
    // inode->i_dev设备号, nr块号
    int nr = bmap(inode,(filp->f_pos)/BLOCK_SIZE);
    struct buffer_head *bh=bread(inode->i_dev,nr);
    ...
    char * p = nr + bh->b_data;
    while (chars-->0)
         put_fs_byte(*(p++),buf++);
    ...
}
```,
caption: [file_read - 简化版]
)

首先 `bmap` 获取全局数据块号，然后 `bread` 将数据块的数据从硬盘设备复制到缓冲区，然后 `put_fs_byte` 再以字节为单位将缓冲区数据复制到用户指定的内存的`buf`中。

=== `bmap`：获取全局的数据块号

第一个函数调用，`bmap`。

#figure(
```c
// file_dev.c
int file_read(struct m_inode * inode, struct file * filp, char * buf, int count) {
    ...
    int nr = bmap(inode,(filp->f_pos)/BLOCK_SIZE);
    ...}

// inode.c
int bmap(struct m_inode * inode,int block) {
    return _bmap(inode,block,0);
}

static int _bmap(struct m_inode * inode,int block,int create) {
    ...
    if (block<0)
        ...
    if (block >= 7+512+512*512)
        ...
    if (block<7) 
        // zone[0] 到 zone[7] 采用直接索引，可以索引小于 7 的块号
        ...
    if (block<512)
        // zone[7] 是一次间接索引，可以索引小于 512 的块号
        ...
    // zone[8] 是二次间接索引，可以索引大于 512 的块号
}
```,
caption: [bmap]
)

整个条件判断的结构是根据 `block` 来划分的。`block` 就是要读取的块号，之所以要划分，就是因为 inode 在记录文件所在块号时，采用了多级索引的方式。`zone[0]` 到 `zone[6]` 采用直接索引，`zone[7]` 是一次间接索引，`zone[8]` 是二次间接索引。

#figure(caption: [])[#image("images/chapter40-4.png", width: 80%)]

刚开始读，块号肯定从零开始，先看 `block<7`，通过直接索引读。

#figure(
```c
// inode.c
static int _bmap(struct m_inode * inode,int block,int create) {
    ...
    if (block<7) {
        if (create && !inode->i_zone[block])
            if (inode->i_zone[block]=new_block(inode->i_dev)) {
                inode->i_ctime=CURRENT_TIME;
                inode->i_dirt=1;
            }
        return inode->i_zone[block];
    }
    ...
}
```,
caption: [bmap - 直接索引]
)

由于 `create==0`，也就是并不需要创建一个新的数据块，所以里面的 if 分支也没了。

#figure(
```c
// inode.c
static int _bmap(struct m_inode * inode,int block,int create) {
    ...
    if (block<7) {
        ...
        return inode->i_zone[block];
    }
    ...
}
```,
caption: [bmap - 直接索引返回]
)

`bmap` 返回的，就是要读入的块号，从全局看在块设备的哪个逻辑块号下。即假如我想要读这个文件的第一个块号的数据，该函数返回的事你这个文件的第一个块在整个硬盘中的哪个块中。

=== `bread`：读入到高速缓冲块

回到 `file_read` 函数接着看，将`bmap`获取的数据块号对应数据块读入到高速缓冲块

#figure(
```c
// file_dev.c
int file_read(struct m_inode * inode, struct file * filp, char * buf, int count) {
    ...
    while (left) {
        if (nr = bmap(inode,(filp->f_pos)/BLOCK_SIZE)) {
            if (!(bh=bread(inode->i_dev,nr)))
    }
}
// buffer.c
// dev设备号(inode->i), block数据块号(nr)
struct buffer_head * bread(int dev,int block)
{
    struct buffer_head * bh;
    if (!(bh=getblk(dev,block)))
        panic("bread: getblk returned NULL\n");
    if (bh->b_uptodate)
        return bh;
    // 否则我们就调用底层快设备读写ll_rw_block函数，产生读设备块请求。
    ll_rw_block(READ,bh);
    ...
}
```,
caption: [bread - part1]
)

`bread` 方法就是根据一个设备号 `dev` 和一个数据块号 `block`，将这个数据块的数据，从硬盘复制到缓冲区里(`buffer_init`里提及)。 而 `getblk` 方法，就是根据设备号 `dev` 和数据块号 `block`，申请到一个缓冲块。

先根据 `hash` 结构快速查找这个 `dev` 和 `block` 是否有对应存在的缓冲块。
#figure(caption: [])[#image("images/chapter40-5.png", width: 60%)]

如果没有，那就从之前建立好的双向链表结构的头指针 `free_list` 开始寻找，直到找到一个可用的缓冲块。
#figure(caption: [])[#image("images/chapter40-6.png", width: 40%)]

具体代码逻辑，还包含当缓冲块正在被其他进程使用，或者缓冲块对应的数据已经被修改时的处理逻辑。

#figure(
```c
// buffer.c
struct buffer_head * bread(int dev,int block) {
    struct buffer_head * bh = getblk(dev,block);
    ...
}

struct buffer_head * getblk(int dev,int block) {
    struct buffer_head * tmp, * bh;

repeat:
    // 先从 hash 结构中找
    if (bh = get_hash_table(dev,block))
        return bh;

    // 如果没有就从 free_list 开始找遍双向链表
    tmp = free_list;
    do {
        if (tmp->b_count)
            continue;
        if (!bh || BADNESS(tmp)<BADNESS(bh)) {
            bh = tmp;
            if (!BADNESS(tmp))
                break;
        }
    } while ((tmp = tmp->b_next_free) != free_list);

    // 如果还没找到，那就说明没有缓冲块可用了，就先阻塞住等一会
    if (!bh) {
        sleep_on(&buffer_wait);
        goto repeat;
    }

    // 到这里已经说明申请到了缓冲块，但有可能被其他进程上锁了
    // 如果上锁了的话，就先等等
    wait_on_buffer(bh);
    if (bh->b_count)
        goto repeat;

    // 到这里说明缓冲块已经申请到，且没有上锁
    // 但还得看 dirt 位，也就是有没有被修改
    // 如果被修改了，就先重新从硬盘中读入新数据
    while (bh->b_dirt) {
        sync_dev(bh->b_dev);
        wait_on_buffer(bh);
        if (bh->b_count)
            goto repeat;
    }
    if (find_buffer(dev,block))
        goto repeat;

    // 给刚刚获取到的缓冲头 bh 重新赋值
    // 并调整在双向链表和 hash 表中的位置
    bh->b_count=1;
    bh->b_dirt=0;
    bh->b_uptodate=0;
    remove_from_queues(bh);
    bh->b_dev=dev;
    bh->b_blocknr=block;
    insert_into_queues(bh);
    return bh;
}
```,
caption: [getblk]
)

经过 `getblk` 之后，就在内存中找到了一处缓冲块，用来接下来存储硬盘中指定数据块的数据。

=== `ll_rw_block`:把硬盘中的数据读取到`buf`

可以看到`ll_rw_block`->`make_request`->`add_request`->`do_hd_request`->`hd_out`的调用链
#figure(
```c
// buffer.c
struct buffer_head * bread(int dev,int block) {
    ...
    ll_rw_block(READ,bh);
    ...
}

void ll_rw_block (int rw, struct buffer_head *bh) {
    ...
    make_request(major, rw, bh);
}

struct request request[NR_REQUEST] = {0};
static void make_request(int major,int rw, struct buffer_head * bh) {
    struct request *req;
    ...
    // 从 request 队列找到一个空位
    if (rw == READ)
        req = request+NR_REQUEST;
    else
        req = request+((NR_REQUEST*2)/3);
    while (--req >= request)
        if (req->dev<0)
            break;
    ...
    // 构造 request 结构
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

// ll_rw_blk.c
static void add_request (struct blk_dev_struct *dev, struct request *req) {
    struct request * tmp;
    req->next = NULL;
    cli();
    // 清空 dirt 位
    if (req->bh)
        req->bh->b_dirt = 0;
    // 当前请求项为空，那么立即执行当前请求项
    if (!(tmp = dev->current_request)) {
        dev->current_request = req;
        sti();
        (dev->request_fn)();
        return;
    }
    // 插入到链表中
    for ( ; tmp->next ; tmp=tmp->next)
        if ((IN_ORDER(tmp,req) ||
            !IN_ORDER(tmp,tmp->next)) &&
            IN_ORDER(req,tmp->next))
            break;
    req->next=tmp->next;
    tmp->next=req;
    sti();
}
```,
caption: [ll_rw_block]
)

主线是从 `request` 数组中找到一个空位，然后作为链表项插入到 `request` 链表中。没错 `request` 是一个 32 大小的数组，里面的每一个 `request` 结构间通过 `next` 指针相连又形成链表。

#figure(caption: [])[#image("images/chapter40-8.png", width: 70%)]

`request` 的具体结构是。

#figure(
```c
// blk.h
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


表示一个读盘的请求参数。
#figure(caption: [])[#image("images/chapter40-9.png", width: 30%)]

有了这些参数，底层方法拿到这个结构之后，就知道怎么样访问硬盘了。那是谁不断从这个 `request` 队列中取出 `request` 结构并对硬盘发起读请求操作的呢？这里 Linux 0.11 有个很巧妙的设计。

==== `add_request`

注意到 `add_request` 方法有如下分支。

#figure(
```c
// blk.h
struct blk_dev_struct {
    void (*request_fn)(void);
    struct request * current_request;
};

// ll_rw_blk.c
struct blk_dev_struct blk_dev[NR_BLK_DEV] = {
    { NULL, NULL },     /* no_dev */
    { NULL, NULL },     /* dev mem */
    { NULL, NULL },     /* dev fd */
    { NULL, NULL },     /* dev hd */
    { NULL, NULL },     /* dev ttyx */
    { NULL, NULL },     /* dev tty */
    { NULL, NULL }      /* dev lp */
};

static void make_request(int major,int rw, struct buffer_head * bh) {
    ...
    add_request(major+blk_dev,req);
}

static void add_request (struct blk_dev_struct *dev, struct request *req) {
    ...
    // 当前请求项为空，那么立即执行当前请求项
    if (!(tmp = dev->current_request)) {
        ...
        (dev->request_fn)();
        ...
    }
    ...
}
```,
caption: [add_request - part1]
)

当设备的当前请求项为空，即第一次收到硬盘操作请求时，会立即执行该设备的 `request_fn` 方法。当前设备的设备号是 3，也就是硬盘，会从 `blk_dev` 数组中取索引下标为 3 的设备结构。在 `hd_init` 已经提及设备号为 3 的`request_fn` 被赋值为硬盘请求函数 `do_hd_request` 。

#figure(
```c
// hd.c
void hd_init(void) {
    blk_dev[3].request_fn = do_hd_request;
    ...
}
```,
caption: [hd_init]
)

==== `do_hd_request`

所以，刚刚的 `request_fn` 背后的具体执行函数，就是这个 `do_hd_request`。去掉了根据起始扇区号计算对应硬盘的磁头 `head`、柱面 `cyl`、扇区号 `sec` 等信息的代码。

#figure(
```c
#define CURRENT (blk_dev[MAJOR_NR].current_request)
// hd.c
void do_hd_request(void) {
    ...
    unsigned int dev = MINOR(CURRENT->dev);
    unsigned int block = CURRENT->sector;
    ...
    nsect = CURRENT->nr_sectors;
    ...
    if (CURRENT->cmd == WRITE) {
        hd_out(dev,nsect,sec,head,cyl,WIN_WRITE,&write_intr);
        ...
    } else if (CURRENT->cmd == READ) {
        hd_out(dev,nsect,sec,head,cyl,WIN_READ,&read_intr);
    } else
        panic("unknown hd-command");
}
```,
caption: [do_hd_request - 简化版]
)

可以看到最终会根据当前请求是写（`WRITE`）还是读（`READ`），在调用 `hd_out` 时传入不同的参数。`hd_out` 就是读硬盘的最底层的函数了。

#figure(
```c
// hd.c
static void hd_out(unsigned int drive,unsigned int nsect,unsigned int sect,
        unsigned int head,unsigned int cyl,unsigned int cmd,
        void (*intr_addr)(void))
{
    ...
    do_hd = intr_addr;
    outb_p(hd_info[drive].ctl,HD_CMD);
    port=HD_DATA;
    outb_p(hd_info[drive].wpcom>>2,++port);
    outb_p(nsect,++port);
    outb_p(sect,++port);
    outb_p(cyl,++port);
    outb_p(cyl>>8,++port);
    outb_p(0xA0|(drive<<4)|head,++port);
    outb(cmd,++port);
}
```,
caption: [hd_out]
)

最底层的读盘请求就是向一堆外设端口做读写操作。这个函数实际上在 `time_init` 为了讲解与 CMOS 外设交互方式的时候讲过。

#tip("Tip")[
在硬盘准备数据时，当前时间片完成就会切换到其他进程执行。
]

#align(center,
three-line-table[
|端口  |读                              |写|
| -    | -                              |-|
|0x1F0 |数据寄存器                    |数据寄存器|
|0x1F1 |错误寄存器                    |特征寄存器|
|0x1F2 |扇区计数寄存器                    |扇区计数寄存器|
|0x1F3 |扇区号寄存器或 LBA 块地址 0~7    |扇区号或 LBA 块地址 0~7|
|0x1F4 |磁道数低 8 位或 LBA 块地址 8~15    |磁道数低 8 位或 LBA 块地址 8~15|
|0x1F5 |磁道数高 8 位或 LBA 块地址 16~23|磁道数高 8 位或 LBA 块地址 16~23|
|0x1F6 |驱动器/磁头或 LBA 块地址 24~27    |驱动器/磁头或 LBA 块地址 24~27|
|0x1F7 |命令寄存器或状态寄存器            |命令寄存器|
]
)

读硬盘就是，往除了第一个以外的后面几个端口写数据，告诉要读硬盘的哪个扇区，读多少。然后再从 `0x1F0` 端口一个字节一个字节的读数据。这就完成了一次硬盘读操作。

从 `0x1F0` 端口读出硬盘数据，是在硬盘读好数据并放在 `0x1F0` 后发起的硬盘中断，进而执行硬盘中断处理函数里进行的。在 `hd_init` 的时候，已经将 `hd_interrupt` 设置为硬盘中断处理函数，中断号是 `0x2E`。

=== `wait_on_buffer`: 挂起当前进程直到 I/O 完成（缓冲区解锁）

经历了`ll_rw_block`->`make_request`->`add_request`->`do_hd_request`->`hd_out`的调用链后，硬盘已经开始准备数据，主流程返回到`wait_on_buffer`

#figure(
```c
// dev设备号(inode->i), block数据块号(nr)
struct buffer_head * bread(int dev,int block)
{
    // 调用底层快设备读写ll_rw_block函数，产生读设备块请求。
    ll_rw_block(READ,bh);
    // 然后等待指定数据块被读入，并等待缓冲区解锁。(在这里就切换到了其他进程执行, 等待硬盘准备好数据发中断)
    wait_on_buffer(bh);
    // 在睡眠醒来之后，如果该缓冲区已更新，则返回缓冲区头指针，退出。否则表明读设备操作失败，于是释放该缓冲区，返回NULL，退出。
    if (bh->b_uptodate)
        return bh;
    // 释放缓冲区
    brelse(bh);
    return NULL;
}
```,
caption: [bread - part2]
)

`wait_on_buffer`主要就是等待指定缓冲块解锁，来看看`wait_on_buffer`的细节
#figure(
```c
static inline void wait_on_buffer(struct buffer_head * bh)
{
    cli();                          // 关中断
    while (bh->b_lock)              // 如果已被上锁则进程进入睡眠，等待其解锁
        sleep_on(&bh->b_wait);
    sti();                          // 开中断
}
```,
caption: [wait_on_buffer]
)

如果指定的缓冲块`bh`已经上锁(说明硬盘需要准备数据)就让进程不可中断地睡眠在该缓冲块的等待队列`b_wait`中。(此时在`sleep_on`中就会调度其他进程执行)在缓冲块解锁时，其等待队列上的所有进程将被唤醒。

#figure(
```c
// sched.c
void sleep_on (struct task_struct **p) {
    struct task_struct *tmp;
    ...
    tmp = *p;
    *p = current;
    current->state = TASK_UNINTERRUPTIBLE;
    schedule();
    if (tmp)
        tmp->state = 0;
}
```,
caption: [sleep_on]
)

虽然是在关闭中断(`cli`)之后去睡眠的，但这样做并不会影响在其他进程上下文中影响中断。因为每个进程都在自己的TSS段中保存了标志寄存器`EFLAGS`的值，所以在进程切换时CPU中当前EFLAGS的值也随之改变。使用`sleep_on`进入睡眠状态的进程需要用`wake_up`明确地唤醒。

==== `make_request`: 缓冲区上锁

那缓冲区是什么时候上锁的呢？是在`make_request`中：

#figure(
```c
static void make_request(int major,int rw, struct buffer_head * bh)
{
    struct request * req;
    int rw_ahead;
        ...
    lock_buffer(bh);
    if ((rw == WRITE && !bh->b_dirt) || (rw == READ && bh->b_uptodate)) {
        unlock_buffer(bh);
        return;
    }
}
```,
caption: [make_request]
)

首先调用 `lock_buffer` 防止其他进程对同一缓冲区进行操作。接着if语句有两个检查：
- 写请求检查：如果是写操作，但缓冲区没有脏标记（`b_dirt` 为假），说明数据无需写回。
- 读请求检查：如果是读操作，但缓冲区数据已经是最新（`b_uptodate` 为真），无需从设备读取数据。

如果上述条件满足，就意味着不需要新的缓冲区，则解锁缓冲区并直接返回。

所以上锁就说明硬盘需要准备数据。进入`lock_buffer`看看
#figure(
```c
static inline void lock_buffer(struct buffer_head * bh)
{
    cli(); // 关中断
    while (bh->b_lock)  // 检查锁状态：如果缓冲区已被其他进程锁定，将当前进程加入等待队列 b_wait 并休眠。
        sleep_on(&bh->b_wait);  // 睡眠等待: 直到锁被释放（unlock_buffer 唤醒），当前进程会重新被调度执行。
    bh->b_lock=1; // 锁定当前缓冲区
    sti();
}

static inline void unlock_buffer(struct buffer_head * bh)
{
    // 缓冲区本身没上锁
    if (!bh->b_lock)
        printk("ll_rw_block.c: buffer not locked\n\r");
    bh->b_lock = 0; // 清除缓冲区中的锁
    wake_up(&bh->b_wait); // 唤醒等待在 b_wait 队列中的所有进程，使其重新尝试获取锁。
}
```,
caption: [lock_buffer && unlock_buffer]
)

=== `hd_interrupt`

在硬盘读完数据后，发起 `0x2E` 中断，便会进入到 `hd_interrupt` 方法里。

#figure(
```c
// system_call.s
_hd_interrupt:
    ...
    xchgl _do_hd,%edx
    ...
    call *%edx
    ...
    iret
```,
caption: [hd_interrupt]
)

这个方法主要是调用 `do_hd` 方法，这个方法是一个函数指针，读操作的时候，将会指向 `read_intr` 这个具体实现。

#figure(
```c
// hd.c
void do_hd_request(void) {
    ...
    } else if (CURRENT->cmd == READ) {
        hd_out(dev,nsect,sec,head,cyl,WIN_READ,&read_intr);
    }
    ...
}

static void hd_out(..., void (*intr_addr)(void)) {
    ...
    do_hd = intr_addr;
    ...
}
```,
caption: [hd_out]
)
`read_intr` 方法继续看。

#figure(
```c
// hd.c
#define port_read(port,buf,nr) \
__asm__("cld;rep;insw"::"d" (port),"D" (buf),"c" (nr):"cx","di")

static void read_intr(void) {
    ...
    // 从数据端口读出数据到内存
    port_read(HD_DATA,CURRENT->buffer,256);
    CURRENT->errors = 0;
    CURRENT->buffer += 512;
    CURRENT->sector++;
    // 还没有读完，则直接返回等待下次
    if (--CURRENT->nr_sectors) {
        do_hd = &read_intr;
        return;
    }
    // 所有扇区都读完了
    // 删除本次都请求项
    end_request(1);
    // 再次触发硬盘操作
    do_hd_request();
}
```,
caption: [read_intr]
)

使用了 `port_read` 宏定义的方法，从端口 `HD_DATA` 中读 256 次数据，每次读一个字，总共就是 512 字节的数据。
- 如果没有读完发起读盘请求时所要求的字节数，那么直接返回，等待下次硬盘触发中断并执行到 `read_intr` 即可。
- 如果已经读完了，就调用 `end_request` 方法将请求项清除掉，然后再次调用 `do_hd_request` 方法循环往复。

重点就在于，结束掉本次请求的 `end_request` 方法。

#figure(
```c
// blk.h
#define CURRENT (blk_dev[MAJOR_NR].current_request)

extern inline void end_request(int uptodate) {
    DEVICE_OFF(CURRENT->dev);
    if (CURRENT->bh) {
        CURRENT->bh->b_uptodate = uptodate;
        unlock_buffer(CURRENT->bh);
    }
    ...
    wake_up(&CURRENT->waiting);
    wake_up(&wait_for_request);
    CURRENT->dev = -1;
    CURRENT = CURRENT->next;
}
```,
caption: [end_request]
)

两个 `wake_up` 方法。
- 第一个唤醒了该请求项所对应的进程 `&CURRENT->waiting`，告诉这个进程这个请求项的读盘操作处理完了，继续执行吧。
- 另一个是唤醒了`request`队列里面有空闲位置的任务，因为 `request` 队列满了没有将请求项插进来的进程`&wait_for_request`。

随后，将当前设备的当前请求项 `CURRENT`，即 `request` 数组里的一个请求项 `request` 的 `dev` 置空，并将当前请求项指向链表中的下一个请求项。
#figure(caption: [])[#image("images/chapter40-10.png", width: 70%)]

这样，`do_hd_request` 方法处理的就是下一个请求项的内容了，直到将所有请求项都处理完毕。整个流程就这样形成了闭环，通过这样的机制，可以做到好似存在一个额外的进程，在不断处理 `request` 链表里的读写盘请求一样。

#figure(caption: [])[#image("images/chapter40-11.png", width: 70%)]

当设备的当前请求项为空时，也就是没有在执行的块设备请求项时，`ll_rw_block` 就会在执行到 `add_request` 方法时，直接执行 `do_hd_request` 方法发起读盘请求。

如果已经有在执行的请求项了，就插入 `request` 链表中。 `do_hd_request` 方法执行完毕后，硬盘发起读或写请求，执行完毕后会发起硬盘中断，进而调用 `read_intr` 中断处理函数。

`read_intr` 会改变当前请求项指针指向 `request` 链表的下一个请求项，并再次调用 `do_hd_request` 方法。所以 `do_hd_request` 方法一旦调用，就会不断处理 `request` 链表中的一项一项的硬盘请求项，这个循环就形成了！

=== `put_fs_byte`：将 `bread` 读入的缓冲块数据复制到用户指定的内存中

现在已经成功地把硬盘中的一个数据块的数据，一个字节都不差地复制到了刚刚申请好的缓冲区里。

#figure(
```c
// file_dev.c
int file_read(struct m_inode * inode, struct file * filp, char * buf, int count) {
    ...
    int  nr = bmap(inode,(filp->f_pos)/BLOCK_SIZE);
    struct buffer_head *bh=bread(inode->i_dev,nr);
    ...
    char * p = nr + bh->b_data;
    while (chars-->0)
         put_fs_byte(*(p++),buf++);
    ...
}
```,
caption: [file_read - put_fs_byte]
)

这个过程，仅仅是内存之间的复制，所以不必紧张。

#figure(
```c
// segment.h
extern _inline void
put_fs_byte (char val, char *addr) {
    __asm__ ("movb %0,%%fs:%1"::"r" (val),"m" (*addr));
}
```,
caption: [put_fs_byte]
)

改成较为好看的样子。（参考赵炯《Linux 内核完全注释 V1.9.5》）

#figure(
```c
// segment.h
extern _inline void
put_fs_byte (char val, char *addr) {
    _asm mov ebx,addr
    _asm mov al,val;
    _asm mov byte ptr fs:[ebx],al;
}
```,
caption: [put_fs_byte - 美化版]
)

其实就是三个汇编指令的 `mov` 操作。

至此，就将数据从硬盘读入缓冲区，再从缓冲区读入用户内存
#figure(caption: [])[#image("images/chapter40-7.png", width: 60%)]

首先通过 `verify_area` 对内存做了校验，需要写时复制的地方在这里提前进行。接下来，`file_read` 方法做了读盘的全部操作，通过 `bmap` 获取到了硬盘全局维度的数据块号，然后 `bread` 将数据块数据复制到缓冲区，然后 `put_fs_byte` 再将缓冲区数据复制到用户内存。

#pagebreak()
