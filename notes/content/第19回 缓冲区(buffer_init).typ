#import "../template.typ": *

= 缓冲区(buffer_init)

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

这个函数传了个参数 `buffer_memory_end`，这个是在`mem_init`就设置好的。

假设内存只有 8M，把一些不相干的分支去掉，方便理解。
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
caption: [buffer_init]
)

先看第一行

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

这里有个外部变量 `end`(内核程序和缓冲区的分界)，而我们的缓冲区开始位置 `start_buffer` 就等于这个变量的内存地址。这个外部变量 `end` 并不是操作系统代码写就的，而是由链接器 `ld` 在链接整个程序时设置的一个外部变量，帮我们计算好了整个内核代码的末尾地址。那在这之前的是内核代码区域肯定不能用，在这之后的，就给 `buffer` 用了。所以我们的内存分布图可以更精确一点了。

#figure(caption: [])[#image("images/chapter19-1.png", width: 60%)]

主内存和缓冲区的分界线，就直接代码里写死了，就是上图中的 2M。可kernel占多大内存在写的时候完全不知道，就算知道了如果改动一点代码也会变化，所以就由程序编译链接时由链接器程序帮我们把这个内核代码末端的地址计算出来，作为一个外部变量 `end` 拿来即用，就方便多了。

#figure(
```c
void buffer_init(long buffer_end) {
    struct buffer_head * h = start_buffer;
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
- 一个是 `buffer_head` 结构的 `h`，代表缓冲头，其指针值是 `start_buffer`，刚刚计算过了，就是图中的内核代码末端地址 `end`，也就是缓冲区开头。
- 一个是 `b`，代表缓冲块，指针值是 `buffer_end`，也就是图中的 2M，就是缓冲区结尾。

缓冲区结尾的 `b` 每次循环 `-1024`，也就是一个缓冲块的值，缓冲区结尾的 `h` 每次循环 `+1`（一个 `buffer_head` 大小的内存），直到碰一块为止。

#figure(caption: [])[#image("images/chapter19-2.png", width: 50%)]

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

#figure(caption: [])[#image("images/chapter19-4.png", width: 40%)]

`free_list` 指向了缓冲头双向链表的第一个结构，然后就可以顺着这个结构，从双向链表中遍历到任何一个缓冲头结构了，而通过缓冲头又可以找到这个缓冲头对应的缓冲块。简单说，缓冲头就是具体缓冲块的管理结构，而 `free_list` 开头的双向链表又是缓冲头的管理结构，整个管理体系就这样建立起来了。

还有最后一个事，能帮助更好管理，往下看。

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

一个 307 大小的 `hash_table` 数组，这个代码在 `buffer.c` 中，而 `buffer.c` 是在 `fs` 包下的，也就是文件系统包下的。所以它今后是为文件系统而服务，具体是内核程序如果需要访问块设备中的数据，就都需要经过缓冲区来间接地操作。也就是说，读取块设备的数据（硬盘中的数据），需要先读到缓冲区中，如果缓冲区已有了，就不用从块设备读取了，直接取走。

那怎么知道缓冲区已经有了要读取的块设备中的数据呢？从双向链表从头遍历当然可以，但是这效率可太低了。所以需要一个 `hashmap` 的结构方便快速查找，这就是 `hash_table` 这个数组的作用。

之后当要读取某个块设备上的数据时，首先要搜索相应的缓冲块，是下面这个函数。

#figure(
```c
#define _hashfn(dev,block) (((unsigned)(dev^block))%307)
#define hash(dev,block) hash_table[_hashfn(dev,block)]

// 搜索合适的缓冲块 
struct buffer_head * getblk(int dev,int block) {
    ...
    struct buffer_head bh = get_hash_table(dev,block)；
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
一路跟下来发现，就是通过 `dev^block % 307` 即 `(设备号^逻辑块号) Mod 307`

找到在 `hash_table` 里的索引下标，如果冲突就形成链表。
#figure(caption: [])[#image("images/chapter19-5.png")]

哈希表 + 双向链表，很容易想到这可以实现 LRU 算法，之后的缓冲区使用和弃用，正是这个算法发挥了作用。也就是之后在讲通过文件系统来读取硬盘文件时，都需要使用和弃用这个缓冲区里的内容，缓冲区即是用户进程的内存和硬盘之间的桥梁。

#pagebreak()
