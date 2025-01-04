#import "../template.typ":*

= 拿到硬盘信息

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

先看一下`init`整体结构(已经把单纯的日志打印和错误校验逻辑去掉了)

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

`drive_info` 是来自内存 `0x90080` 的数据，`setup.s` 程序将硬盘 1 的参数信息放在这里了，包括柱面数、磁头数、扇区数等信息。`setup` 是个系统调用，会通过中断最终调用到 `sys_setup` 函数。

看 `sys_setup` 函数，仍然是去掉了日志打印和错误判断分支，并且仅当作只有一块硬盘，去掉了一层 for 循环。
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
    hd[0].nr_sects = 
        hd_info[0].head * hd_info[0].sect * hd_info[0].cyl;
    
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

第一部分，硬盘基本信息的赋值的操作。

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
    ...
}
```,
caption: [sys_setup - part1]
)

入参 `BIOS` 是来自内存 `0x90080` 的数据，一开始先往 `hd_info` 数组的 0 索引处存上这些信息。我们假设就只有一块硬盘，所以这个数组也只有一个元素。

#figure(
```c
这个数组里的结构就是 hd_i_struct，就表示硬盘的参数。

struct hd_i_struct {
    // 磁头数、每磁道扇区数、柱面数、写前预补偿柱面号、磁头着陆区柱面号、控制字节
    int head,sect,cyl,wpcom,lzone,ctl;
};
struct hd_i_struct hd_info[] = {}；
```,
caption: [hd_info]
)

#figure(caption: [])[#image("images/chapter29-1.png", width: 70%)]

#figure(
```c
第二部分，硬盘分区表的设置。

static struct hd_struct {
    long start_sect;
    long nr_sects;
} hd[5] = {}

int sys_setup(void * BIOS) {
    ...
    hd[0].start_sect = 0;
    hd[0].nr_sects = 
        hd_info[0].head * hd_info[0].sect * hd_info[0].cyl;
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

就是给 hd 数组的五项附上了值。表示硬盘的分区信息，每个分区用 `start_sect` 和 `nr_sects`，也就是开始扇区和总扇区数来记录。
#figure(caption: [])[#image("images/chapter29-2.png", width: 80%)]

这些信息就是在硬盘的第一个扇区的 `0x1BE` 偏移处，这里存储着该硬盘的分区信息。

所以 `bread` 就是干这事的，从硬盘读取数据。

```c
struct buffer_head *bh = bread(0x300, 0);
```

第一个参数 `0x300` 是第一块硬盘的主设备号，就表示要读取的块设备是硬盘一。第二个参数 0 表示读取第一个块，一个块为 1024 字节大小，也就是连续读取硬盘开始处 0 ~ 1024 字节的数据。拿到这部分数据后，再取 `0x1BE` 偏移处，就得到了分区信息。

```c
struct partition *p = 0x1BE + (void *)bh->b_data;
```

#figure(caption: [])[#image("images/chapter29-3.png", width: 60%)]

至于如何从硬盘中读取指定位置（块）的数据，也就是 `bread` 函数的内部实现，那是相当复杂的，涉及到与缓冲区配合的部分，还有读写请求队列的设置，以及中断。

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

其中 `rd_load` 是当有 ramdisk 时，也就是虚拟内存盘，才会执行。虚拟内存盘是通过软件将一部分内存（RAM）模拟为硬盘来使用的一种技术，我们就先当做没有。

`mount_root` 就是加载根根文件系统，有了它之后，操作系统才能从一个根开始找到所有存储在硬盘中的文件，所以它是文件系统的基石。为了加载根文件系统，就是把硬盘中的数据加载到内存里，以文件系统的数据格式来解读这些信息。所以第一，需要硬盘本身就有文件系统的信息，硬盘不能是裸盘。第二，需要读取硬盘的数据到内存，那就必须需要知道硬盘的参数信息，这就是我们本讲所做的事情的意义。

#pagebreak()
