#import "../template.typ":*

= init 进程

== 拿到硬盘信息

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
caption: [main - init]
)

由于 `fork` 函数一调用，就又多出了一个进程，子进程（进程 1）会返回 `0`，父进程（进程 0）返回子进程的 `ID`，所以 `init` 函数只有进程 `1` 才会执行。

先看一下`init`整体结构(已经把日志打印和错误校验逻辑去掉了)

#figure(
```c
void init(void) {
    int pid,i;
    setup((void *) &drive_info);
    (void) open("/dev/tty0",O_RDWR,0);
    (void) dup(0);
    (void) dup(0);
    if (!(pid=fork())) {
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
    }
    if (pid>0)
        while (pid != wait(&i))
            /* nothing */;
    while (1) {
        if (!pid=fork()) {
            close(0);close(1);close(2);
            setsid();
            (void) open("/dev/tty0",O_RDWR,0);
            (void) dup(0);
            (void) dup(0);
            _exit(execve("/bin/sh",argv,envp));
        }
        while (1)
            if (pid == wait(&i))
                break;
        sync();
    }
    _exit(0);   /* NOTE! _exit, not exit() */
}
```,
caption: [init]
)

=== `setup((void *) &drive_info)`

#figure(
```c
struct drive_info { char dummy[32]; } drive_info;

// drive_info = (*(struct drive_info *)0x90080);

void init(void) {
    setup((void *) &drive_info);
    ...
}
```,
caption: [init - setup]
)

- `setup` 是个系统调用，会通过中断最终调用到 `sys_setup` 函数。
- `drive_info` 是来自内存 `0x90080` 的数据，`setup.s` 程序将硬盘 1 的参数信息放在这里了，包括柱面数、磁头数、扇区数等信息。

`sys_setup` 函数，去掉日志打印和错误判断分支，并且当作只有一块硬盘，去掉了一层 for 循环。

#figure(
```c
int sys_setup(void * BIOS) {
    hd_info[0].cyl = *(unsigned short *) BIOS;
    hd_info[0].head = *(unsigned char *) (2+BIOS);
    hd_info[0].wpcom = *(unsigned short *) (5+BIOS);
    hd_info[0].ctl = *(unsigned char *) (8+BIOS);
    hd_info[0].lzone = *(unsigned short *) (12+BIOS);
    hd_info[0].sect = *(unsigned char *) (14+BIOS);
    BIOS += 16;

    hd[0].start_sect = 0;
    hd[0].nr_sects = hd_info[0].head * hd_info[0].sect * hd_info[0].cyl;

    struct buffer_head *bh = bread(0x300, 0);
    struct partition *p = 0x1BE + (void *)bh->b_data;
    for (int i=1;i<5;i++,p++) {
        hd[i].start_sect = p->start_sect;
        hd[i].nr_sects = p->nr_sects;
    }
    brelse(bh);

    rd_load();
    mount_root();
    return (0);
}
```,
caption: [sys_setup - 简化版]
)

==== 硬盘基本信息的赋值的操作

#figure(
```c
// 硬盘参数的结构体
struct hd_i_struct {
    // 磁头数、每磁道扇区数、柱面数、写前预补偿柱面号、磁头着陆区柱面号、控制字节
    int head,sect,cyl,wpcom,lzone,ctl;
};
struct hd_i_struct hd_info[] = {}；

int sys_setup(void * BIOS) {
    hd_info[0].cyl = *(unsigned short *) BIOS;
    hd_info[0].head = *(unsigned char *) (2+BIOS);
    hd_info[0].wpcom = *(unsigned short *) (5+BIOS);
    hd_info[0].ctl = *(unsigned char *) (8+BIOS);
    hd_info[0].lzone = *(unsigned short *) (12+BIOS);
    hd_info[0].sect = *(unsigned char *) (14+BIOS);
    BIOS += 16;
    ...
}
```,
caption: [sys_setup - part1]
)

入参 `BIOS` 是来自内存 `0x90080` 的数据，一开始先往 `hd_info` 数组的 0 索引处存上这些信息。假设就只有一块硬盘，所以这个数组也只有一个元素。

#figure(caption: [])[#image("images/chapter29-1.png", width: 70%)]

==== 硬盘分区表的设置

#figure(
```c
static struct hd_struct {
    long start_sect;
    long nr_sects;
} hd[5] = {}

int sys_setup(void * BIOS) {
    ...
    hd[0].start_sect = 0;
    hd[0].nr_sects = hd_info[0].head * hd_info[0].sect * hd_info[0].cyl;

    struct buffer_head *bh = bread(0x300, 0);
    struct partition *p = 0x1BE + (void *)bh->b_data;
    for (int i=1;i<5;i++,p++) {
        hd[i].start_sect = p->start_sect;
        hd[i].nr_sects = p->nr_sects;
    }
    brelse(bh);
    ...
}
```,
caption: [sys_setup - part2]
)

就是给 `hd` 数组的五项附上了值。表示硬盘的分区信息，每个分区用 `start_sect` 和 `nr_sects`，也就是开始扇区和总扇区数来记录。

#figure(caption: [])[#image("images/chapter29-2.png", width: 80%)]

这些信息就是在硬盘的第一个扇区的 `0x1BE` 偏移处，这里存储着该硬盘的分区信息。所以 `bread` 就是干这事的，从硬盘读取数据。

```c
struct buffer_head *bh = bread(0x300, 0);
```

- 第一个参数 `0x300` 是第一块硬盘的主设备号，就表示要读取的块设备是硬盘一。
- 第二个参数 0 表示读取第一个块，一个块为 1024 字节，也就是连续读取硬盘开始处 0 ~ 1023 字节的数据。拿到这部分数据后，再取 `0x1BE` 偏移处，就得到了分区信息。

```c
struct partition *p = 0x1BE + (void *)bh->b_data;
```

#figure(caption: [])[#image("images/chapter29-3.png", width: 60%)]

至于如何从硬盘中读取指定位置（块）的数据，也就是 `bread` 函数的内部实现，相当复杂，涉及到与缓冲区配合的部分，还有读写请求队列的设置，以及中断，姑且搁置。

#figure(
```c
int sys_setup(void * BIOS) {
    ...
    rd_load();
    mount_root();
    return (0);
}
```,
caption: [sys_setup - part3]
)

其中 `rd_load` 是当有 ramdisk 时，也就是虚拟内存盘，才会执行。虚拟内存盘是通过软件将一部分内存（RAM）模拟为硬盘来使用的一种技术，就先当做没有。

`mount_root` 就是加载根根文件系统，有了它之后，操作系统才能从一个根开始找到所有存储在硬盘中的文件，所以它是文件系统的基石。为了加载根文件系统，就是把硬盘中的数据加载到内存里，以文件系统的数据格式来解读这些信息。所以第一，需要硬盘本身就有文件系统的信息，硬盘不能是裸盘。第二，需要读取硬盘的数据到内存，那就必须需要知道硬盘的参数信息。

== 加载根文件系统

#figure(
```c
void mount_root(void) {
    int i,free;
    struct super_block * p;
    struct m_inode * mi;

    for(i=0;i<64;i++)
        file_table[i].f_count=0;

    for(p = &super_block[0] ; p < &super_block[8] ; p++) {
        p->s_dev = 0;
        p->s_lock = 0;
        p->s_wait = NULL;
    }
    p=read_super(0);
    mi=iget(0,1);

    mi->i_count += 3 ;
    p->s_isup = p->s_imount = mi;
    current->pwd = mi;
    current->root = mi;
    free=0;
    i=p->s_nzones;
    while (-- i >= 0)
        if (!set_bit(i&8191,p->s_zmap[i>>13]->b_data))
            free++;

    free=0;
    i=p->s_ninodes+1;
    while (-- i >= 0)
        if (!set_bit(i&8191,p->s_imap[i>>13]->b_data))
            free++;
}
```,
caption: [mount_root]
)

整体上，就是要把硬盘中的数据，以文件系统的格式进行解读，加载到内存中设计好的数据结构，这样操作系统就可以通过内存中的数据，以文件系统的方式访问硬盘中的一个个文件了。

#figure(caption: [])[#image("images/chapter30-1.png", width: 80%)]

那搞清楚两个事情即可：
- 第一，硬盘中的文件系统格式
- 第二，内存中用于文件系统的数据结构

=== 硬盘中的文件系统格式

硬盘中的文件系统，无非就是硬盘中的一堆数据，按照固定格式去解析。Linux-0.11 中是 MINIX 文件系统。

#figure(caption: [MINIX 文件系统])[#image("images/chapter30-2.png", width: 75%)]

每一个块结构的大小是 1024 字节，也就是 1KB，硬盘里的数据就按照这个结构，妥善地安排在硬盘里。

可是硬盘中凭什么就有了这些信息呢？这就是个鸡生蛋蛋生鸡的问题了。可以先写一个操作系统，然后给一个硬盘做某种文件系统类型的格式化，这样就得到一个有文件系统的硬盘了，有了这个硬盘，操作系统就可以成功启动了。

简单看看 MINIX 文件系统的格式。

- *引导块*就是最开头说的启动区，当然不一定所有的硬盘都有启动区，但还是得预留出这个位置，以保持格式的统一。
- *超级块*用于描述整个文件系统的整体信息，看它的字段就知道了，有后面的 inode 数量，块数量，第一个块在哪里等信息。有了它，整个硬盘的布局就清晰了。
- *inode 位图和块位图*，就是位图的基本操作和作用了，表示后面 inode 和块的使用情况，和之前讲的内存占用位图 `mem_map[]` 是类似的。
- *inode* 存放着每个文件或目录的元信息和索引信息，元信息就是文件类型、文件大小、修改时间等，索引信息就是大小为 9 的 `i_zone[9]` 块数组，表示这个文件或目录的具体数据占用了哪些块。其中块数组里，0~6 表示直接索引，7 表示一次间接索引，8 表示二次间接索引。当文件比较小时，比如只占用 2 个块就够了，那就只需要 `zone[0]` 和 `zone[1]` 两个直接索引即可。
- 存放具体文件或目录实际信息的数据块了。如果是一个普通文件类型的 inode 指向的块，那里面就直接是文件的二进制信息。如果是一个目录类型的 inode 指向的块，那里面存放的就是这个目录下的文件和目录的 inode 索引以及文件或目录名称等信息。

=== 内存中用于文件系统的数据结构

#figure(
```c
struct file {
    unsigned short f_mode;
    unsigned short f_flags;
    unsigned short f_count;
    struct m_inode * f_inode;
    off_t f_pos;
};

void mount_root(void) {
    for(i=0;i<64;i++)
        file_table[i].f_count=0;
    ...
}
```,
caption: [mount_root - part2]
)

把 64 个 `file_table` 里的 `f_count` 清零。

这个 `file_table` 表示进程所使用的文件，进程每使用一个文件，都需要记录在这里，包括文件类型、文件 inode 索引信息等，而这个 `f_count` 表示被引用的次数，此时还没有引用，所以设置为零。而这个 `file_table`的索引（准确说是进程的`filp`索引），就是通常说的文件描述符。

比如 `echo "hello" > 0` 就表示把 `"hello"` 输出到 0 号文件描述符(就是 `file_table[0]` 所表示的文件)

注意到 `file` 结构里有个 `f_inode` 字段，通过 `f_inode` 即可找到它的 `inode` 信息，`inode` 信息包含了一个文件所需要的全部信息，包括文件的大小、文件的类型、文件所在的硬盘块号，这个所在硬盘块号，就是文件的位置咯。

#figure(
```c
struct super_block super_block[8];
void mount_root(void) {
    ...
    struct super_block * p;
    for(p = &super_block[0] ; p < &super_block[8] ; p++) {
        p->s_dev = 0;
        p->s_lock = 0;
        p->s_wait = NULL;
    }
    ...
}
```,
caption: [mount_root - part2]
)

是把 `super_block` 数组做清零工作。这个 `super_block` 的意义是，操作系统与一个设备以文件形式进行读写访问时，就需要把这个设备的超级块信息放在这里。这样通过这个超级块，就可以掌控这个设备的文件系统全局了。

#figure(
```c
void mount_root(void) {
    ...
    // 读取硬盘的超级块信息到内存中来。
    p=read_super(0);
    // 读取根 inode (根目录所在inode)信息
    mi=iget(0,1);

    mi->i_count += 3 ;
    p->s_isup = p->s_imount = mi;

    // 然后把该 inode 设置为当前进程（也就是进程 1）的当前工作目录和根目录。
    current->pwd = mi;
    current->root = mi;

    // 然后记录块位图信息。
    free=0;
    i=p->s_nzones;
    while (-- i >= 0)
        if (!set_bit(i&8191,p->s_zmap[i>>13]->b_data))
            free++;

    // 最后记录 inode 位图信息。
    free=0;
    i=p->s_ninodes+1;
    while (-- i >= 0)
        if (!set_bit(i&8191,p->s_imap[i>>13]->b_data))
            free++;
}
```,
caption: [mount_root - part3]
)

== 打开终端设备文件

=== `open`: 打开终端设备文件

`setup` 函数加载了根文件系统，顺着根 inode 可以找到所有文件，下一行 `open` 函数可以通过文件路径，从硬盘中把一个文件的信息方便地拿到。

#figure(
```c
void init(void) {
    setup((void *) &drive_info);
    (void) open("/dev/tty0",O_RDWR,0);
    (void) dup(0);
    (void) dup(0);
}
```,
caption: [init - part1]
)

`open` 函数会触发 `0x80` 中断，最终调用到 `sys_open` 这个系统调用函数(`open.c`)。

#figure(
```c
struct file file_table[64] = {0};

int sys_open(const char * filename,int flag,int mode) {
    struct m_inode * inode;
    struct file * f;
    int i,fd;
    mode &= 0777 & ~current->umask;

    for(fd=0 ; fd<20; fd++)
        if (!current->filp[fd])
            break;
    if (fd>=20)
        return -EINVAL;
    current->close_on_exec &= ~(1<<fd);

    f=0+file_table;
    for (i=0 ; i<64 ; i++,f++)
        if (!f->f_count) break;
    if (i>=64)
        return -EINVAL;

    (current->filp[fd]=f)->f_count++;

    i = open_namei(filename,flag,mode,&inode);

    if (S_ISCHR(inode->i_mode))
        if (MAJOR(inode->i_zone[0])==4) {
            if (current->leader && current->tty<0) {
                current->tty = MINOR(inode->i_zone[0]);
                tty_table[current->tty].pgrp = current->pgrp;
            }
        } else if (MAJOR(inode->i_zone[0])==5)
            if (current->tty<0) {
                iput(inode);
                current->filp[fd]=NULL;
                f->f_count=0;
                return -EPERM;
            }
    if (S_ISBLK(inode->i_mode))
        check_disk_change(inode->i_zone[0]);

    f->f_mode = inode->i_mode;
    f->f_flags = flag;
    f->f_count = 1;
    f->f_inode = inode;
    f->f_pos = 0;
    return (fd);
}
```,
caption: [sys_open]
)

#figure(caption: [])[#image("images/chapter31-1.png", width: 80%)]

第一步，在进程文件描述符数组 `filp` 中找到一个空闲项。`task_struct` 其中有一个 `filp` 数组的字段，就是文件描述符数组，这里先找到一个空闲项，将空闲地方的索引值记为 `fd`。

#figure(
```c
int sys_open(const char * filename,int flag,int mode) {
    ...
    for(int fd=0 ; fd<20; fd++)
        if (!current->filp[fd])
            break;
    if (fd>=20)
        return -EINVAL;
    ...
}
```,
caption: [sys_open - part1]
)

由于此时当前进程，也就是进程 1，还没有打开过任何文件，所以 0 号索引处就是空闲的，`fd` 自然就等于 `0`。

第二步，在系统文件表 `file_table` 中找到一个空闲项。

#figure(
```c
int sys_open(const char * filename,int flag,int mode) {
    int i;
    ...
    struct file * f=0+file_table;
    for (i=0 ; i<64; i++,f++)
        if (!f->f_count) break;
    if (i>=64)
        return -EINVAL;
    ...
}
```,
caption: [sys_open - part2]
)

注意到，进程的 `filp` 数组大小是 `20`，系统的 `file_table` 大小是 `64`，可以得出，每个进程最多打开 `20` 个文件，整个系统最多打开 `64` 个文件。

第三步，将进程的文件描述符数组项和系统的文件表项，对应起来(就是把*系统文件表项*复制到*进程的文件描述符表*里)，代码中就是一个赋值操作。

#figure(
```c
int sys_open(const char * filename,int flag,int mode) {
    ...
    current->filp[fd] = f;
    ...
}
```,
caption: [sys_open - part3]
)

第四步，根据文件名从文件系统中找到这个文件。其实相当于找到了这个 `tty0` 文件对应的 inode 信息。

#figure(
```c
int sys_open(const char * filename,int flag,int mode) {
    ...
    // filename = "/dev/tty0"
    // flag = O_RDWR 读写
    // 不是创建新文件，所以 mode 没用
    // inode 是返回参数
    open_namei(filename,flag,mode,&inode);
    ...
}
```,
caption: [sys_open - parrt4]
)

接下来判断 `tty0` 这个 inode 是否是字符设备，如果是字符设备文件，那么如果设备号是 4 的话，则设置当前进程的 `tty` 号为该 inode 的子设备号。并设置当前进程`tty` 对应的`tty` 表项的父进程组号等于进程的父进程组号。(暂不展开)

最后第五步，填充 `file` 数据。其实就是初始化这个 `f`，包括刚刚找到的 inode 值。最后返回给上层文件描述符 `fd` 的值，也就是0。

#figure(
```c
int sys_open(const char * filename,int flag,int mode) {
    ...
    f->f_mode = inode->i_mode;
    f->f_flags = flag;
    f->f_count = 1;
    f->f_inode = inode;
    f->f_pos = 0;
    return (fd);
    ...
}
```,
caption: [sys_open - part5]
)

`open` 函数，就是在上述操作后，返回一个 `int` 型的数值 `fd`，称作文件描述符。之后就可以对着这个文件描述符进行读写。之所以可以这么方便，是由于通过这个文件描述符，最终能够找到其对应文件的 inode 信息，就能够找到它在磁盘文件中的位置进行读写。

比如读/写函数的系统调用入口。

#figure(
```c
int sys_read (unsigned int fd, char *buf, int count) {
    ...
}
int sys_write (unsigned int fd, char *buf, int count) {
    ...
}
```,
caption: [sys_write && sys_write]
)

入参都有个 `int` 型的文件描述符 `fd`，就是刚刚 `open` 时返回的。

=== `dup`: `stdout` && `stderr`
#figure(
```c
void init(void) {
    setup((void *) &drive_info);
    (void) open("/dev/tty0",O_RDWR,0);
    (void) dup(0);
    (void) dup(0);
}
```,
caption: [init - part2]
)

接着再往下看两行代码。接下来，两个一模一样的 `dup` 函数。
- 刚刚的 `open` 函数返回的为 `0` 号 `fd`，这个作为标准输入设备。
- 接下来的 `dup` 为 `1` 号 `fd` 赋值，这个作为标准输出设备。
- 再接下来的 `dup` 为 `2` 号 `fd` 赋值，这个作为标准错误输出设备。

就是常说的 `stdin`、`stdout`、`stderr`。

`dup` 首先仍然是通过系统调用方式，调用到 `sys_dup` 函数。把一些错误校验的旁路逻辑去掉了。

#figure(
```c
int sys_dup(unsigned int fildes) {
    return dupfd(fildes,0);
}

// fd 是要复制的文件描述符
// arg 是指定新文件描述符的最小数值
static int dupfd(unsigned int fd, unsigned int arg) {
    ...
    while (arg < 20)
        if (current->filp[arg])
            arg++;
        else
            break;
    ...
    (current->filp[arg] = current->filp[fd])->f_count++;
    return arg;
}
```,
caption: [sys_dup]
)

就是从进程的 `filp` 中找到下一个空闲项，然后把要复制的文件描述符 `fd` 的信息，统统复制到这里。根据上下文，这一步其实就是把 0 号文件描述符，复制到 1 号文件描述符，那么 0 号和 1 号文件描述符，就统统可以通过一条路，找到最终 `tty0` 这个设备文件的 inode 信息了。

#figure(caption: [])[#image("images/chapter31-2.png", width: 60%)]

那下一个 `dup` 同理

#figure(caption: [])[#image("images/chapter31-3.png", width: 60%)]

此时进程 1 已经比进程 0 多了与 外设交互的能力，具体说来是与`tty0` 这个外设（也是个文件，因为 Linux 下一切皆文件）交互的能力。因为进程 `fork` 出自己子进程的时候，这个 `filp` 数组也会被复制，那么当进程 1 `fork` 出进程 2 时，进程 2 也会拥有这样的映射关系，也可以操作 `tty0` 这个设备

而进程 0 是不具备与外设交互的能力的，因为它并没有打开任何的文件，filp 数组也就没有任何作用。进程 1 刚刚创建的时候，是 `fork` 的进程 0，所以也不具备这样的能力，而通过 `setup` 加载根文件系统，`open` 打开 `tty0` 设备文件等代码，使得进程 1 具备了与外设交互的能力，同时也使得之后从进程 1 `fork` 出来的进程 2 也天生拥有和进程 1 同样的与外设交互的能力。

#figure(
```c
void init(void) {
    ...
    printf("%d buffers = %d bytes buffer space\n\r",NR_BUFFERS, \
        NR_BUFFERS*BLOCK_SIZE);
    printf("Free mem: %d bytes\n\r",memory_end-main_memory_start);
}
```,
caption: [init - part2]
)

最后两行是个打印语句，就是基于刚刚打开并创建的 0,1,2 三个文件描述符而做出的操作。1 号文件描述符被当做标准输出，那进入 `printf` 的实现看看有没有用到它。

#figure(
```c
static int printf(const char *fmt, ...) {
    va_list args;
    int i;
    va_start(args, fmt);
    write(1,printbuf,i=vsprintf(printbuf, fmt, args));
    va_end(args);
    return i;
}
```,
caption: [printf]
)

中间有个 `write` 函数，传入了 1 号文件描述符作为第一个参数。细节先不展开，这里知道它肯定是顺着这个描述符寻找到了相应的 `tty0` 也就是终端控制台设备，并输出在了屏幕上。

启动 Linux 0.11 看效果。

#figure(caption: [])[#image("images/chapter31-4.png", width: 70%)]

== 进程2的创建

进程1的创建结束了，接下来是控制流程和创建新进程。

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        close(0);
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
        _exit(2);
    }
    if (pid>0)
        while (pid != wait(&i))
            /* nothing */;
    while (1) {
        if (!(pid=fork())) {
            close(0);close(1);close(2);
            setsid();
            (void) open("/dev/tty0",O_RDWR,0);
            (void) dup(0);
            (void) dup(0);
            _exit(execve("/bin/sh",argv,envp));
        }
        while (1)
            if (pid == wait(&i))
                break;
        printf("\n\rchild %d died with code %04x\n\r",pid,i);
        sync();
    }
    _exit(0);   /* NOTE! _exit, not exit() */
}
```,
caption: [init - rest]
)

=== `fork` + `execve`

先看这个第一段

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        close(0);
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
        _exit(2);
    }
    ...
}
```,
caption: [init - part3]
)

1. `fork` 一个新的子进程，此时就是进程 2 了。
2. 在进程 2 里关闭（`close`） `0` 号文件描述符。
3. 只读形式打开（`open`） `rc` 文件。
4. 然后执行（`execve`） `sh` 程序。

==== `fork`

进程 0 `fork` 出进程 1 就是将进程0的 `task_struct` 结构进行一下复制。再重写一些基本信息，包括元信息和 `tss` 里的寄存器信息。再之后，用 `copy_page_tables` 复制了一下页表（这里涉及到写时复制的伏笔）。

这里的进程 1 fork 出进程 2，也是同样的流程，不同之处在于两点细节：
1. 进程 1 打开了三个文件描述符并指向了 `tty0`，那这个也被复制到进程 2 了，具体说来就是进程结构 `task_struct` 里的 `flip[]` 数组被复制了一份。
  - 而进程 0 `fork` 出进程 1 时是没有复制这部分信息的，因为进程 0 没有打开任何文件。进程 0 没有与外设交互的能力，进程 1 有，其实就是这个 `flip` 数组里有没有东西而已
2. 进程 0 复制进程 1 时页表的复制只有 160 项，也就是映射 640K，而之后进程的复制，统统都是复制 1024 项，也就是映射 4M 空间。
  #figure(
  ```c
  int copy_page_tables(unsigned long from,unsigned long to,long size) {
      ...
      nr = (from==0)?0xA0:1024;
      ...
  }
  ```,
  caption: [copy_page_tables - nr]
  )

#figure(caption: [])[#image("images/chapter32-1.png", width: 60%)]

==== `close`

继续看。

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        close(0);
        open("/etc/rc",O_RDONLY,0);
        execve("/bin/sh",argv_rc,envp_rc);
        _exit(2);
    }
    ...
}
```,
caption: [init - part4]
)

`fork` 完之后，后面 `if` 里面的代码都是进程 2 在执行了。`close(0)` 就是关闭 0 号文件描述符，也就是进程 1 复制过来的打开了 `tty0` 并作为标准输入的文件描述符，那么此时 0 号文件描述符就空出来了。

下面是 `close` 对应的系统调用函数，很简单。

#figure(
```c
int sys_close(unsigned int fd) {
    ...
    current->filp[fd] = NULL;
    ...
}
```,
caption: [sys_close]
)

==== `open`

接下来 `open` 函数以只读形式打开了一个叫 `/etc/rc` 的文件，刚好占据了 0 号文件描述符的位置。

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        ...
        open("/etc/rc",O_RDONLY,0);
        ...
    }
    ...
}
```,
caption: [init - open]
)

这个 `rc` 文件表示配置文件，具体什么内容，取决于硬盘里这个位置处放了什么内容，与内核无关，暂且不用管。

此时，进程 2 与进程 1 几乎完全一样，只不过进程 2 通过 `close` 和 `open` 操作，将原来进程 1 的指向标准输入的 0 号文件描述符，重新指向了 `/etc/rc` 文件。而这个 `rc` 文件是后面 `sh` 程序要用到的。

==== `execve`

`execve` 函数调用，使进程2摇身一变，成为 `/bin/sh` 程序继续运行！

#figure(
```c
void init(void) {
    ...
    if (!(pid=fork())) {
        ...
        execve("/bin/sh",argv_rc,envp_rc);
        ...
    }
    ...
}
```,
caption: [init - execve]
)

这里就包含着操作系统究竟是如何加载并执行一个程序的原理，包括如何从文件系统中找到这个文件，如何解析一个可执行文件（在现代的 Linux 里称作 ELF 可执行文件），如何讲可执行文件中的代码和数据加载到内存并运行。加载到内存并运行又包含着虚拟内存等相关的知识。

== `execve`

先打开 `execve`，开一下它的调用链。

#figure(
```c
static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

// 调用方
execve("/bin/sh",argv_rc,envp_rc);

// 宏定义
_syscall3(int,execve,const char *,file,char **,argv,char **,envp)

// 通过系统调用进入到这里
EIP = 0x1C
_sys_execve:
    lea EIP(%esp),%eax
    pushl %eax
    call _do_execve
    addl $4,%esp
    ret

// 最终执行的函数
int do_execve(
        unsigned long * eip,
        long tmp,
        char * filename,
        char ** argv,
        char ** envp) {
    ...
}
```,
caption: [execve 的调用链]
)

入参：
- `eip` 调用方触发系统调用时由 CPU 压入栈空间中的 `eip` 的指针 。
- `tmp` 是一个无用的占位参数。
- `filename` 是 `"/bin/sh"`
- `argv` 是 `{ "/bin/sh", NULL }`
- `envp` 是 `{ "HOME=/", NULL }`

=== `do_execve`
#figure(
```c
int do_execve(...) {
    // 检查文件类型和权限等
    ...
    // 读取文件的第一块数据到缓冲区
    ...
    // 如果是脚本文件，走这里
    if (脚本文件判断逻辑) {
        ...
    }
    // 如果是可执行文件，走这里
    // 一堆校验可执行文件是否能执行的判断
    ...
    // 进程管理结构的调整
    ...
    // 释放进程占有的页面
    ...
    // 调整线性地址空间、参数列表、堆栈地址等
    ...
    // 设置 eip 和 esp，这里是 execve 变身大法的关键！
    eip[0] = ex.a_entry;
    eip[3] = p;
    return 0;
    ...
}
```,
caption: [do_execve 结构]
)

1. 检查文件类型和权限等
2. 读取文件的第一块数据到缓冲区
3. 脚本文件与可执行文件的判断
4. 校验可执行文件是否能执行
5. 进程管理结构的调整
6. 释放进程占有的页面
7. 调整线性地址空间、参数列表、堆栈地址等
8. 设置 `eip` 和 `esp`，完成摇身一变

核心逻辑就是*加载文件、调整内存、开始执行*

==== 读取文件开头 1KB 的数据

#figure(
```c
先是根据文件名，找到并读取文件里的内容

// exec.c
int do_execve(...) {
    ...
    // 根据文件名 /bin/sh 获取 inode
    struct m_inode * inode = namei(filename);
    // 根据 inode 读取文件第一块数据（1024KB）
    struct buffer_head * bh = bread(inode->i_dev,inode->i_zone[0]);
    ...
}
```,
caption: [do_execve - part1]
)

代码里 `inode -> i_zone[0]` 就刚好是文件开头的 1KB 数据。现在这 1KB 的数据，就已经在内存中了，但还没有解析。

==== 解析这 1KB 的数据为 `exec` 结构

接下来的工作就是解析它，本质上就是按照指定的数据结构来解读罢了。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    struct exec ex = *((struct exec *) bh->b_data);
    ...
}
```,
caption: [do_execve - exec]
)

先从刚刚读取文件返回的缓冲头指针中取出数据部分 `bh -> data`，也就是文件前 1024 个字节，此时还是一段读不懂的二进制数据。然后按照 `exec` 这个结构体对其进行解析，它便有了生命。

#figure(
```c
struct exec {
    // 魔数
    unsigned long a_magic;
    // 代码区长度
    unsigned a_text;
    // 数据区长度
    unsigned a_data;
    // 未初始化数据区长度
    unsigned a_bss;
    // 符号表长度
    unsigned a_syms;
    // 执行开始地址
    unsigned a_entry;
    // 代码重定位信息长度
    unsigned a_trsize;
    // 数据重定位信息长度
    unsigned a_drsize;
};
```,
caption: [struct exec]
)

上面的代码就是 `exec` 结构体，这是 `a.out` 格式文件的头部结构，现在的 Linux 已经弃用了这种古老的格式，改用 ELF 格式了，但大体的思想是一致的。

==== 判断是脚本文件还是可执行文件
Linux 脚本文件前面有这么一坨。

#figure(
```sh
#!/bin/sh
#!/usr/bin/python
```,
caption: [shebang]
)

通常可以直接执行这样的文件，原因就在下面这个代码里。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    if ((bh->b_data[0] == '#') && (bh->b_data[1] == '!') {
        ...
    }
    brelse(bh);
    ...
}
```,
caption: [brelse]
)

判断前面两个字符是不是 `#!`，是就走脚本文件的执行逻辑。

现在的 `/bin/sh` 是个可执行的二进制文件，所以直接看外面，执行可执行二进制文件的逻辑。

第一步就是 `brelse` 释放这个缓冲块，因为已经把这个缓冲块内容解析成 `exec` 结构保存到程序的栈空间里了，那么这个缓冲块就可以释放，用于其他读取磁盘时的缓冲区。

==== 准备参数空间

执行 `/bin/sh` 时，还传了 `argc` 和 `envp` 参数，就是下面这代码实现的。

#figure(
```c
#define PAGE_SIZE 4096
#define MAX_ARG_PAGES 32

// exec.c
int do_execve(...) {
    ...
    // p = 0x1FFFC = 128K - 4
    unsigned long p = PAGE_SIZE * MAX_ARG_PAGES - 4;
    ...
    // p = 0x1FFF5 = 128K - 4 - 7
    p = copy_strings(envc,envp,page,p,0);
    // p = 0x1FFED = 128K - 4 - 7 - 8
    p = copy_strings(argc,argv,page,p,0);
    ...
    // p = 0x3FFFFED = 64M - 4 - 7 - 8
    p += change_ldt(ex.a_text,page)-MAX_ARG_PAGES*PAGE_SIZE;
    // p = 0x3FFFFD0
    p = (unsigned long) create_tables((char *)p,argc,envc);
    ...
    // 设置栈指针
    eip[3] = p;
}
```,
caption: [do_execve - 参数]
)

准备参数空间的过程，同时也伴随着一个表示地址的 `unsigned long p` 的计算轨迹。

开头一行计算出的 p 值为 `p = 4096 * 32 - 4 = 0x20000 - 4 = 128K - 4`。这表示参数表，每个进程的参数表大小为 128K，就表示每个进程的线性地址空间的末端 128K，是为参数表保留的，目前这个 p 就指向了参数表的开始处（偏移 4 字节）。

#figure(caption: [])[#image("images/chapter33-1.png", width: 60%)]

接下来两个 `copy_strings` 就是往这个参数表里面存放信息，不过具体存放的只是字符串常量值的信息，随后他们将被引用，有点像 Java 里 class 文件的字符串常量池思想。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    // p = 0x1FFF5 = 128K - 4 - 7
    p = copy_strings(envc,envp,page,p,0);
    // p = 0x1FFED = 128K - 4 - 7 - 8
    p = copy_strings(argc,argv,page,p,0);
    ...
}
```,
caption: [do_execve - copy_strings]
)

具体说来，`envp` 表示字符串参数 `"HOME=/"`，`argv` 表示字符串参数 `"/bin/sh"`，两个 copy 就表示把这个字符串参数往参数表里存，相应地指针 `p` 也往下移动（共移动了 7 + 8 = 15 个字节），和压栈的效果是一样的。

#figure(caption: [])[#image("images/chapter33-2.png", width: 60%)]

实际上这些字符串都是紧挨着的，通过 debug 查看参数表位置处的内存便可以看到真正存放的方式。

#figure(caption: [])[#image("images/chapter33-3.png", width: 70%)]

两个字符串被安排在了参数表内存处，且参数与参数之间用 `00` 也就是 `NULL` 来分隔。

接下来是更新局部描述符。

#figure(
```c
#define PAGE_SIZE 4096
#define MAX_ARG_PAGES 32

// exec.c
int do_execve(...) {
    ...
    // p = 0x3FFFFED = 64M - 4 - 7 - 8
    p += change_ldt(ex.a_text,page)-MAX_ARG_PAGES*PAGE_SIZE;
    ...
}
```,
caption: [do_execve - change_ldt]
)

就是根据 `ex.a_text` 修改局部描述符中的代码段限长 `code_limit`。`ex` 结构里的 `a_text` 是生成 `/bin/sh` 这个 `a.out` 格式的文件时，写在头部的值，用来表示代码段的长度。至于具体是怎么生成的，无需关心。

由于这个函数返回值是数据段限长，也就是 64M，所以最终的 `p` 值被调整为了以每个进程的线性地址空间视角下的地址偏移。

#figure(caption: [])[#image("images/chapter33-4.png", width: 60%)]

接下来就是真正构造参数表的环节了。

#figure(
```c
#define PAGE_SIZE 4096
#define MAX_ARG_PAGES 32

// exec.c
int do_execve(...) {
    ...
    // p = 0x3FFFFD0
    p = (unsigned long) create_tables((char *)p,argc,envc);
    ...
}
```,
caption: [do_execve - create_tables]
)

刚刚仅仅是往参数表里面丢入了需要的字符串常量值信息，现在就需要真正把参数表构建起来。

展开 `create_tables`。

#figure(
```c
/*
 * create_tables() parses the env- and arg-strings in new user
 * memory and creates the pointer tables from them, and puts their
 * addresses on the "stack", returning the new stack pointer value.
 */
static unsigned long * create_tables(char * p,int argc,int envc) {
    unsigned long *argv,*envp;
    unsigned long * sp;

    sp = (unsigned long *) (0xfffffffc & (unsigned long) p);
    sp -= envc+1;
    envp = sp;
    sp -= argc+1;
    argv = sp;
    put_fs_long((unsigned long)envp,--sp);
    put_fs_long((unsigned long)argv,--sp);
    put_fs_long((unsigned long)argc,--sp);
    while (argc-->0) {
        put_fs_long((unsigned long) p,argv++);
        while (get_fs_byte(p++)) /* nothing */ ;
    }
    put_fs_long(0,argv);
    while (envc-->0) {
        put_fs_long((unsigned long) p,envp++);
        while (get_fs_byte(p++)) /* nothing */ ;
    }
    put_fs_long(0,envp);
    return sp;
}
```,
caption: [create_tables]
)

一行一行仔细分析，不难分析出参数表空间。

#figure(caption: [])[#image("images/chapter33-5.png", width: 30%)]

最后，将 `sp` 返回给 `p`，这个 `p` 将作为一个新的栈顶指针，给即将要完成替换的 `/bin/sh` 程序，也就是下面的代码。

#figure(
```c
// exec.c
int do_execve(...) {
    ...
    // 设置栈指针
    eip[3] = p;
}
```,
caption: [do_execve - 设置栈指针]
)

为什么这样操作就可以达到更换栈顶指针的作用呢？那结合着更换代码指针 PC 来进行讲解。

==== 设置 `eip` 和 `esp`

下面这两行就是 `execve` 的关键，解释了为什么能变成一个新程序开始执行。

#figure(
```c
// exec.c
int do_execve(unsigned long * eip, ...) {
    ...
    eip[0] = ex.a_entry;
    eip[3] = p; 
    ...
}
```,
caption: [设置eip和esp]
)

一个新程序开始执行，本质上就是，代码指针 `eip` 和栈指针 `esp` 指向了一个新的地方。

代码指针 `eip` 决定了 CPU 将执行哪一段指令，栈指针 `esp` 决定了 CPU 压栈操作的位置，以及读取栈空间数据的位置，在高级语言视角下就是局部变量以及函数调用链的栈帧。

所以这两行代码，第一行重新设置了代码指针 `eip` 的值，指向 `/bin/sh` 这个 `a.out` 格式文件的头结构 `exec` 中的 `a_entry` 字段，表示该程序的入口地址。

第二行重新设置了栈指针 `esp` 的值，指向了经过一路计算得到的 `p`，也就是图中 `sp` 的值。将这个值作为新的栈顶。

==== 计算机的世界没有魔法

至于为什么往 `eip` 的 `0` 和 `3` 索引位置处写入数据，就可以达到替换 `eip` 和 `esp` 的目的，那就得看看这个 `eip` 变量是怎么来的了。

#figure(
```c
static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

// 调用方
execve("/bin/sh",argv_rc,envp_rc);

// 宏定义
_syscall3(int,execve,const char *,file,char **,argv,char **,envp)

// 通过系统调用进入到这里
EIP = 0x1C
_sys_execve:
    lea EIP(%esp),%eax
    pushl %eax
    call _do_execve
    addl $4,%esp
    ret

// exec.c
int do_execve(unsigned long * eip, ...) {
    ...
    eip[0] = ex.a_entry;
    eip[3] = p; 
    ...
}
```,
caption: [execve 调用链]
)

`do_execve` 函数，是通过一开始的 `execve` 函数触发了系统调用来到的这里。系统调用是一种中断，前面说过，中断时 CPU 会给栈空间里压入一定的信息，这部分信息是死的，查手册可以查得到。

#figure(caption: [])[#image("images/chapter33-6.png", width: 60%)]

然后，进入中断以后，通过系统调用查表进入到 `_sys_execve` 这里。

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

在真正调用 `do_execve` 函数时，`_sys_execve` 这段代码插入了一个小步骤，就是把当前栈顶指针 `esp` 偏移到 `EIP` 处的地址值给当做第一个参数 `unsigned long * eip` 传入进来了。

而偏移 `EIP` 处的位置，恰好就是中断时压入的 `EIP` 的值的位置，表示中断发生前的指令寄存器的值。所以 `eip[0]` 就表示栈空间里的 `EIP` 位置，`eip[3]` 就表示栈空间里的 `ESP` 位置。

#figure(caption: [])[#image("images/chapter33-7.png", width: 60%)]

由于现在处于中断，所以中断返回后，也就是 `do_execve` 这个函数 `return` 之后，就会寻找中断返回前的这几个值（包括 `eip` 和 `esp`）进行恢复。所以如果把这个栈空间里的 `eip` 和 `esp` 进行替换，换成执行 `/bin/sh` 所需要的 `eip` 和 `esp`，那么中断返回的"恢复"工作，就犹如"跳转"到一个新程序那里一样，其实是欺骗了 CPU，达到了 `execve` 这个函数的魔法效果。

== shell程序

以xv6里的shell实现为例，仍然去掉多余的校验逻辑

#figure(
```c
// xv6-public sh.c
int main(void) {
    static char buf[100];
    // 读取命令
    while(getcmd(buf, sizeof(buf)) >= 0){
        // 创建新进程
        if(fork() == 0)
            // 执行命令
            runcmd(parsecmd(buf));
        // 等待进程退出
        wait();
    }
}
```,
caption: [xv6 - shell简化版]
)

总得来说，shell 程序就是个死循环，在死循环里面，shell 就是不断读取（`getcmd`）用户输入的命令，创建一个新的进程（`fork`），在新进程里执行（`runcmd`）刚刚读取到的命令，最后等待（`wait`）进程退出，再次进入读取下一条命令的循环中。

shell 就是不断 fork + execve 完成执行一个新程序的功能的，那 `execve` 就藏在 `runcmd` 代码了。

#figure(
```c
void runcmd(struct cmd *cmd) {
    ...
    struct execcmd ecmd = (struct execcmd*)cmd;
    ...
    exec(ecmd->argv[0], ecmd->argv);
    ...
}
```,
caption: [runcmd]
)

省略了很多代码，比如遇到管道命令 PIPE，遇到命令集合 LIST 时的处理逻辑，仅仅看单纯执行一条命令的逻辑。就是简简单单调用了个 `exec` 函数
