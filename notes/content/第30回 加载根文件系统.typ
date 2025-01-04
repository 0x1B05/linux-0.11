#import "../template.typ":*

= 加载根文件系统.typ

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

从整体上说，它就是要把硬盘中的数据，以文件系统的格式进行解读，加载到内存中设计好的数据结构，这样操作系统就可以通过内存中的数据，以文件系统的方式访问硬盘中的一个个文件了。

#figure(caption: [])[#image("images/chapter30-1.png", width: 90%)]

那其实搞清楚两个事情即可：
- 第一，硬盘中的文件系统格式
- 第二，内存中用于文件系统的数据结构

== 硬盘中的文件系统格式

硬盘中的文件系统，无非就是硬盘中的一堆数据，按照一定格式去解析罢了。Linux-0.11 中的文件系统是 MINIX 文件系统。

#figure(caption: [])[#image("images/chapter30-2.png", width: 75%)]

每一个块结构的大小是 1024 字节，也就是 1KB，硬盘里的数据就按照这个结构，妥善地安排在硬盘里。


可是硬盘中凭什么就有了这些信息呢？这就是个鸡生蛋蛋生鸡的问题了。你可以先写一个操作系统，然后给一个硬盘做某种文件系统类型的格式化，这样你就得到一个有文件系统的硬盘了，有了这个硬盘，你的操作系统就可以成功启动了。

简单看看 MINIX 文件系统的格式。

- *引导块*就是我们系列最开头说的启动区，当然不一定所有的硬盘都有启动区，但我们还是得预留出这个位置，以保持格式的统一。
- *超级块*用于描述整个文件系统的整体信息，我们看它的字段就知道了，有后面的 inode 数量，块数量，第一个块在哪里等信息。有了它，整个硬盘的布局就清晰了。
- *inode 位图和块位图*，就是位图的基本操作和作用了，表示后面 inode 和块的使用情况，和我们之前讲的内存占用位图 mem_map[] 是类似的。
- *inode* 存放着每个文件或目录的元信息和索引信息，元信息就是文件类型、文件大小、修改时间等，索引信息就是大小为 9 的 `i_zone[9]` 块数组，表示这个文件或目录的具体数据占用了哪些块。其中块数组里，0~6 表示直接索引，7 表示一次间接索引，8 表示二次间接索引。当文件比较小时，比如只占用 2 个块就够了，那就只需要 `zone[0]` 和 `zone[1]` 两个直接索引即可。
- 存放具体文件或目录实际信息的数据块了。如果是一个普通文件类型的 inode 指向的块，那里面就直接是文件的二进制信息。如果是一个目录类型的 inode 指向的块，那里面存放的就是这个目录下的文件和目录的 inode 索引以及文件或目录名称等信息。

== 内存中用于文件系统的数据结构

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

把 64 个 `file_table` 里的 `f_count` 清零。这个 `file_table` 表示进程所使用的文件，进程每使用一个文件，都需要记录在这里，包括文件类型、文件 inode 索引信息等，而这个 `f_count` 表示被引用的次数，此时还没有引用，所以设置为零。而这个 `file_table` 的索引（当然准确说是进程的`filp`索引才是），就是我们通常说的文件描述符。

比如有如下命令。

```sh
echo "hello" > 0
```

就表示把 "hello" 输出到 0 号文件描述符(就是 `file_table[0]` 所表示的文件)

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

是把一个数组 `super_block` 做清零工作。这个 `super_block` 存在的意义是，操作系统与一个设备以文件形式进行读写访问时，就需要把这个设备的超级块信息放在这里。这样通过这个超级块，就可以掌控这个设备的文件系统全局了。

接下来的操作，就是读取硬盘的超级块信息到内存中来。

#figure(
```c
void mount_root(void) {
    ...
    p=read_super(0);
    ...
}
```,
caption: [mount_root - part3]
)

`read_super` 就是读取硬盘中的超级块。

接下来，读取根 `inode` (根目录所在inode)信息。

#figure(
```c
struct m_inode * mi;
void mount_root(void) {
    ...
    mi=iget(0,1);
    ...
}
```,
caption: [mount_root - part4]
)

然后把该 inode 设置为当前进程（也就是进程 1）的当前工作目录和根目录。

#figure(
```c
void mount_root(void) {
    ...
    current->pwd = mi;
    current->root = mi;
    ...
}
```,
caption: [mount_root - part5]
)

然后记录块位图信息。

#figure(
```c
void mount_root(void) {
    ...
    i=p->s_nzones;
    while (-- i >= 0)
        set_bit(i&8191, p->s_zmap[i>>13]->b_data);
    ...
}
```,
caption: [mount_root - part6]
)

最后记录 inode 位图信息。

#figure(
```c
void mount_root(void) {
    ...
    i=p->s_ninodes+1;
    while (-- i >= 0)
        set_bit(i&8191, p->s_imap[i>>13]->b_data);
}
```,
caption: [mount_root - part7]
)

#pagebreak()
