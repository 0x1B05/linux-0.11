#import "../template.typ":*

= 缺页中断

进程 2 通过 `execve` 函数，将自己变成为 `/bin/sh` 程序，也就是 shell 程序开始执行。

#figure(
```c
// main.c
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
caption: [init - execve]
)

此时进程 2 就是 shell 程序了。相当于之前的进程 1 通过 `fork` + `execve` 这两个函数的组合，创建了一个新的进程去加载并执行了 shell 程序。在 Linux 里执行一个程序，比如在命令行中 `./xxx`，其内部实现逻辑都是 `fork + execve` 这个原理。

通过 `execve`，使得下一条 CPU 指令将会执行到 `/bin/sh` 程序所在的内存起始位置处，也就是 `/bin/sh` 头部结构中 `a_entry` 所描述的地址。

有个问题，仅仅将 `/bin/sh` 文件的头部加载到了内存，其他部分并没有进行加载，那怎么执行到的 `/bin/sh` 的程序指令？
#figure(caption: [])[#image("images/chapter34-1.png", width: 50%)]

== 跳转到一个不存在的地址会发生什么

`/bin/sh` 这个文件并不是 Linux 0.11 源码里的内容，Linux 0.11 只管按照 `a.out` 这种格式去解读它，跳转到 `a.out` 格式头部数据结构 `exec.a_entry` 所指向的内存地址去执行指令。所以这个 `a_entry` 的值是多少，完全取决于硬盘中 `/bin/sh` 这个文件是怎么构造的了，假设它为 0，这表示随后的 CPU 将跳转到 0 地址处进行执行。(这个 0 仅仅表示逻辑地址，既没有进行分段，也没有进行分页。)由于现在所处的代码是属于进程 2，所以逻辑地址 0 通过分段机制映射到线性地址空间，就是 `0x8000000`，表示 128M 位置处。
#figure(caption: [])[#image("images/chapter34-2.png", width: 30%)]

128M 这个线性地址，随后将会通过分页机制的映射转化为物理地址，定位到最终的真实物理内存。可128M 这个线性地址并没有页表映射它，因为除了 `/bin/sh` 文件的头部加载到了内存外，其他部分并没有进行加载操作。

再准确点说，是 `0x8000000` 这个线性地址的访问，遇到了页表项的存在位 `P` 等于 `0` 的情况。一旦遇到了这种情况，CPU 会触发一个中断：页错误（Page-Fault），这在 Intel 手册 Volume-3 Chapter 4.7 章节里给出了这个信息。

#figure(caption: [])[#image("images/chapter34-3.png", width: 80%)]
#figure(caption: [])[#image("images/chapter34-4.png", width: 80%)]

当触发这个 Page-Fault 中断后，就会进入 Linux 0.11 源码中的 `page_fault` 方法，由于 Linux 0.11 的 page_fault 是汇编写的，不直观，这里选 Linux 1.0 的代码，逻辑是一样的。

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
caption: [do_page_fault - do_no_page]
)

根据 `error_code` 的不同，有不同的逻辑。刚刚说了，这个中断是由于 `0x8000000` 这个线性地址的访问，遇到了页表项的存在位 `P` 等于 `0` 的情况，所以 `error_code` 的第 `0` 位就是 `0`，会走 `do_no_page` 逻辑。(`do_wp_page` 叫页写保护中断，`do_no_page` 叫缺页中断。)

== 缺页中断 `do_no_page`

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long error_code,unsigned long address) {
    int nr[4];
    unsigned long tmp;
    unsigned long page;
    int block,i;

    address &= 0xfffff000;
    tmp = address - current->start_code;
    if (!current->executable || tmp >= current->end_data) {
        get_empty_page(address);
        return;
    }
    if (share_page(tmp))
        return;
    if (!(page = get_free_page()))
        oom();
/* remember that 1 block is used for header */
    block = 1 + tmp/BLOCK_SIZE;
    for (i=0 ; i<4 ; block++,i++)
        nr[i] = bmap(current->executable,block);
    bread_page(page,current->executable->i_dev,nr);
    i = tmp + 4096 - current->end_data;
    tmp = page + 4096;
    while (i-- > 0) {
        tmp--;
        *(char *)tmp = 0;
    }
    if (put_page(page,address))
        return;
    free_page(page);
    oom();
}
```,
caption: [do_no_page]
)

仍然是去掉一些不重要的分支，假设跳转不会超过数据末端 `end_data`，也没有共享内存页面，申请空闲内存时也不会内存不足产生 `oom` 等，将程序简化如下。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    // 线性地址的页面地址 0x8000000
    address &= 0xfffff000;
    // 计算相对于进程基址的偏移 0
    unsigned long tmp = address - current->start_code;
    // 寻找空闲的一页内存
    unsigned long page = get_free_page();
    // 计算这个地址在文件中的哪个数据块 1
    int block = 1 + tmp/BLOCK_SIZE;
    // 一个数据块 1024 字节，所以一页内存需要读 4 个数据块
    int nr[4];
    for (int i=0 ; i<4 ; block++,i++)
        nr[i] = bmap(current->executable,block);
    bread_page(page,current->executable->i_dev,nr);
    ...
    // 完成页表的映射
    put_page(page,address);
}
```,
caption: [do_no_page - 简化版]
)

首先，缺页产生的线性地址，之前假设过了，是 `0x8000000`，也就是进程 2 自己线性地址空间的起始处 128M 这个位置。由于页表映射是以页为单位的，所以首先计算出 `address` 所在的页，其实就是完成一次 4KB 的对齐。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    // 线性地址的页面地址 0x8000000
    address &= 0xfffff000;
    ...
}
```,
caption: [do_no_page - 对齐]
)

此时 `address` 对齐后仍然是 `0x8000000`。这个地址是整个线性地址空间的地址，但对于进程 2 自己来说，需要计算出相对于进程 2 的偏移地址，也就是去掉进程 2 的段基址部分。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    ...
    // 计算相对于进程基址的偏移 0
    unsigned long tmp = address - current->start_code;
    ...
}
```,
caption: [do_no_page - 计算偏移]
)

这里的 `current->start_code` 就是进程 2 的段基址，也是 128M。

#figure(caption: [])[#image("images/chapter34-5.png", width: 30%)]

所以偏移地址 `tmp` 计算后等于 `0`，这和之前假设的 `a_entry = 0` 是一致的。接下来就是寻找一个空闲页。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    ...
    // 寻找空闲的一页内存
    unsigned long page = get_free_page();
    ...
}
```,
caption: [do_no_page - get_free_page]
)

这个 `get_free_page` 是用汇编语言写的，其实就是去 `mem_map[]` 中寻找一个值为 `0` 的位置，这就表示找到了空闲内存。
#figure(caption: [])[#image("images/chapter34-6.png", width: 70%)]

找到一页物理内存后，当然是把硬盘中的数据加载进来。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    ...
    // 计算这个地址在文件中的哪个数据块 1
    int block = 1 + tmp/BLOCK_SIZE;
    // 一个数据块 1024 字节，所以一页内存需要读 4 个数据块
    int nr[4];
    for (int i=0 ; i<4 ; block++,i++)
        nr[i] = bmap(current->executable,block);
    bread_page(page,current->executable->i_dev,nr);
    ...
}
```,
caption: [do_no_page - 加载硬盘数据]
)

从硬盘首先从 `0` 内存地址开始读，应该就对应着这个文件 `0` 号数据块，当然由于 `/bin/sh` 这个 `a.out` 格式的文件使用了 `1` 个数据块作为头部 `exec` 结构，所以跳过头部，从文件 `1` 号数据块开始读。

因为硬盘中的 1 个数据块为 1024 字节，而一页内存为 4096 字节，所以要读 4 块，这就是 `nr[4]` 的缘故。

之后读取数据主要是两个函数，`bmap` 负责将相对于文件的数据块转换为相对于整个硬盘的数据块，比如这个文件的第 1 块数据，可能对应在整个硬盘的第 24 块的位置。

`bread_page` 就是连续读取 4 个数据块到 1 页内存的函数，这里暂时不展开。

最后一步完成页表的映射。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    ...
    // 完成页表的映射
    put_page(page,address);
}
```,
caption: [do_no_page - 页表映射]
)

因为仅仅是申请了物理内存页，并且把硬盘数据复制了进来，但并没有把这个物理内存页和线性地址空间的内存页进行映射，也就是没建立相关的页表。

#figure(caption: [])[#image("images/chapter34-7.png", width: 60%)]

建立页表的映射，由于 Linux 0.11 使用的是二级页表，所以实际上就是写入页目录项和页表项的过程，我把 `put_page` 函数简化了一下，只考虑页目录项还不存在的场景。

#figure(
```c
// memory.c
unsigned long put_page(unsigned long page,unsigned long address) {
    unsigned long tmp, *page_table;
    // 找到页目录项
    page_table = (unsigned long *) ((address>>20) & 0xffc);
    // 写入页目录项
    tmp = get_free_page();
    *page_table = tmp|7;
    // 写入页表项
    page_table = (unsigned long *) tmp;
    page_table[(address>>12) & 0x3ff] = page | 7;
    return page;
}
```,
caption: [put_page]
)

== 缺页中断返回

本质上就是加载硬盘对应位置的数据，然后建立页表的过程。

#figure(
```c
// memory.c
// address 缺页产生的线性地址 0x8000000
void do_no_page(unsigned long address) {
    // 线性地址的页面地址 0x8000000
    address &= 0xfffff000;
    // 计算相对于进程基址的偏移 0
    unsigned long tmp = address - current->start_code;
    // 寻找空闲的一页内存
    unsigned long page = get_free_page();
    // 计算这个地址在文件中的哪个数据块 1
    int block = 1 + tmp/BLOCK_SIZE;
    // 一个数据块 1024 字节，所以一页内存需要读 4 个数据块
    int nr[4];
    for (int i=0 ; i<4 ; block++,i++)
        nr[i] = bmap(current->executable,block);
    bread_page(page,current->executable->i_dev,nr);
    ...
    // 完成页表的映射
    put_page(page,address);
}
```,
caption: [do_no_page]
)

`execve` 函数返回后，CPU 就跳转到 `/bin/sh` 程序的第一行开始执行，但由于跳转到的线性地址不存在，所以引发了缺页中断，把硬盘里 `/bin/sh` 所需要的内容加载到了内存，此时缺页中断返回。

返回后，CPU 会再次尝试跳转到 `0x8000000` 这个线性地址，此时由于缺页中断的处理结果，使得该线性地址已有对应的页表进行映射，所以顺利地映射到了物理地址，也就是 `/bin/sh` 的代码部分（从硬盘加载过来的），那接下来就终于可以执行 `/bin/sh` 程序，也就是 shell 程序了。

#pagebreak()
