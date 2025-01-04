#import "../template.typ": *

= 硬盘(`hd_init`)

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

一共就四行代码。初始化往往都比较简单，尤其是对硬件设备的初始化，大体都是：

1. 往某些 IO 端口上读写一些数据，表示开启它；
2. 然后再向中断向量表中添加一个中断，使得 CPU 能够响应这个硬件设备的动作；
3. 最后再初始化一些数据结构来管理。不过像是内存管理可能结构复杂些，外设的管理，相对就简单很多了。

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

我们把 `blk_dev` 数组索引 `3` 位置处的块设备管理结构 `blk_dev_struct` 的 `request_fn` 赋值为了 `do_hd_request`：

因为有很多块设备，所以 Linux 0.11 内核用了一个 `blk_dev[]` 来进行管理，每一个索引表示一个块设备。`blk_dev[3]`就是给硬盘留的位置。

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
是不是有点像接口？这其实就是多态思想在 C 语言的体现, 用 Java 程序员熟悉的话就是，父类引用 `request_fn` 指向子类对象 `do_hd_request` 的感觉咯。
]

我们再看第二行。

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

对于中断我们已经很熟悉了，这里就是又设置了一个新的中断，中断号是 `0x2E`，中断处理函数是 `hd_interrupt`，也就是说硬盘发生读写时，硬盘会发出中断信号给 CPU，之后 CPU 便会陷入中断处理程序，也就是执行 `hd_interrupt` 函数。

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

又多了一个中断
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

#tip("Tip")[
  操作系统就是一个靠中断驱动的死循环而已，如果不发生任何中断，操作系统会一直在一个死循环里等待。换句话说，让操作系统工作的唯一方式，就是触发中断。
]

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
