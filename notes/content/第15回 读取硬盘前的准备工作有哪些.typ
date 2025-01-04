#import "../template.typ": *

= 读取硬盘前的准备工作有哪些.typ

读取硬盘数据到内存中，是操作系统的一个基础功能。读取硬盘需要有*块设备驱动程序*，而以文件的方式来读取则还有要再上面包一层*文件系统*。把读出来的数据放到内存，就涉及到*内存中缓冲区的管理*。我们现在主要关注，读取块设备与内存缓冲区之间的桥梁，*块设备请求项的初始化工作*。

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
caption: [request结构体]
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
#figure(caption: [])[#image("images/chapter15-1.png", width: 30%)]
其他的参数，肯定是为了更好地配合操作系统进行读写块设备操作，为了把多个读写块设备请求很好地组织起来。这个组织不但要有这个数据结构中 `hb` 和 `next` 等变量的配合，还要有后面的电梯调度算法的配合...
这个 `request` 结构可以完整描述一个读盘操作。然后那个 `request` 数组就是把它们都放在一起，并且它们又通过 `next` 指针串成链表。
#figure(caption: [])[#image("images/chapter15-2.png", width: 80%)]

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

入参 `fd` 是文件描述符，通过它可以找到一个文件的 `inode`，进而找到这个文件在硬盘中的位置。另两个入参 `buf` 就是要复制到的内存中的位置，`count` 就是要复制多少个字节。

#figure(caption: [])[#image("images/chapter15-3.png", width: 80%)]

#figure(
```c
钻到 file_read 函数里继续看。

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

这个函数就是去读某一个设备的某一个数据块号的内容。

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

其中 `getblk` 先申请了一个内存中的缓冲块，然后 `ll_rw_block` 负责把数据读入这个缓冲块。

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

#h(2em)具体说来，就是该函数会往刚刚的设备的请求项链表 `request[32]` 中添加一个请求项，只要 `request[32]` 中有未处理的请求项存在，都会陆续地被处理，直到设备的请求项链表是空为止。具体怎么读盘，就是与硬盘 IO 端口进行交互的过程了，可以继续往里跟，直到看到一个 `hd_out` 函数为止，这里不展开了。

我们在 `main` 函数的 `init` 系列函数中，通过 `blk_dev_init` 为后面的块设备访问，提前建立了一个数据结构，作为访问块设备和内存缓冲区之间的桥梁。

#pagebreak()
