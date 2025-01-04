#import "../template.typ":*

= 打开终端设备文件.typ

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

第一步，在进程文件描述符数组 `filp` 中找到一个空闲项。`task_struct` 其中有一个 `filp` 数组的字段，就是文件描述符数组，这里先找到一个空闲项，将空闲地方的索引值即为 `fd`。
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

第二步，在系统文件表 `file_table` 中找到一个空闲项。一样的玩法。

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

第三步，将进程的文件描述符数组项和系统的文件表项，对应起来。代码中就是一个赋值操作。

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

第四步，根据文件名从文件系统中找到这个文件。其实相当于找到了这个 tty0 文件对应的 inode 信息。

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

最后第五步，填充 file 数据。其实就是初始化这个 f，包括刚刚找到的 inode 值。最后返回给上层文件描述符 fd 的值，也就是零。

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

open 函数，就是在上述操作后，返回一个 `int` 型的数值 `fd`，称作文件描述符。之后就可以对着这个文件描述符进行读写。

之所以可以这么方便，是由于通过这个文件描述符，最终能够找到其对应文件的 inode 信息，就能够找到它在磁盘文件中的位置进行读写。

比如读函数的系统调用入口。

#figure(
```c
int sys_read (unsigned int fd, char *buf, int count) {
    ...
}
```,
caption: [sys_read]
)

写函数的系统调用入口。

#figure(
```c
int sys_write (unsigned int fd, char *buf, int count) {
    ...
}
```,
caption: [sys_write]
)

入参都有个 `int` 型的文件描述符 `fd`，就是刚刚 `open` 时返回的。

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

就是 Linux 中常说的 `stdin`、`stdout`、`stderr`。

`dup` 首先仍然是通过系统调用方式，调用到 `sys_dup` 函数。仍然是把一些错误校验的旁路逻辑去掉了。

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

就是从进程的 `filp` 中找到下一个空闲项，然后把要复制的文件描述符 `fd` 的信息，统统复制到这里。根据上下文，这一步其实就是把 0 号文件描述符，复制到 1 号文件描述符，那么 0 号和 1 号文件描述符，就统统可以通过一条路子，找到最终 `tty0` 这个设备文件的 inode 信息了。

#figure(caption: [])[#image("images/chapter31-2.png", width: 60%)]

那下一个 `dup` 就自然

#figure(caption: [])[#image("images/chapter31-3.png", width: 60%)]

此时进程 1 已经比进程 0 多了与 外设交互的能力，具体说来是 `tty0` 这个外设（也是个文件，因为 Linux 下一切皆文件）交互的能力。因为进程 fork 出自己子进程的时候，这个 filp 数组也会被复制，那么当进程 1 fork 出进程 2 时，进程 2 也会拥有这样的映射关系，也可以操作 tty0 这个设备

而进程 0 是不具备与外设交互的能力的，因为它并没有打开任何的文件，filp 数组也就没有任何作用。进程 1 刚刚创建的时候，是 fork 的进程 0，所以也不具备这样的能力，而通过 setup 加载根文件系统，open 打开 tty0 设备文件等代码，使得进程 1 具备了与外设交互的能力，同时也使得之后从进程 1 fork 出来的进程 2 也天生拥有和进程 1 同样的与外设交互的能力。

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

#pagebreak()
