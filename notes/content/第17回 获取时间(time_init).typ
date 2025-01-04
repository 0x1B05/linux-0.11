#import "../template.typ": *

= 获取时间(`time_init`)

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

就是对一个端口先 `out` 写一下，再 `in` 读一下。CPU 与外设打交道基本是通过端口，往某些端口写值来表示要这个外设干嘛，然后从另一些端口读值来接受外设的反馈。至于这个外设内部是怎么实现的，对使用它的操作系统而言，是个黑盒，无需关心。

`CMOS` 这个外设比较陌生，以与硬盘的交互为例。
 
最常见的就是读硬盘了，我们看硬盘的端口表。

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

读硬盘即，往除了第一个以外的后面几个端口写数据，告诉要读硬盘的哪个扇区，读多少。然后再从 `0x1F0` 端口读数据。
    1. 在 `0x1F2` 写入要读取的扇区数
    2. 在 `0x1F3` ~ `0x1F6` 这四个端口写入计算好的起始 LBA 地址
    3. 在 `0x1F7` 处写入读命令的指令号
    4. 不断检测 `0x1F7` （此时已成为状态寄存器的含义）的忙位
    5. 如果第四步骤为不忙，则开始不断从 `0x1F0` 处读取数据到内存指定位置，直到读完
 
读取硬盘的这个轮询操作会占用 CPU 的计算资源，可以交给 DMA 设备，但和硬盘的交互，通通都是按照硬件手册上的端口说明，来操作的。
 
回到CMOS，它是主板上的一个可读写的 RAM 芯片，开机时长按某个键就可以进入设置它的页面。

#figure(caption: [])[#image("images/chapter17-1.png")]

`time_init`就是与它打交道，获取它的一些数据而已。

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

前面几个赋值语句 `CMOS_READ` 就是通过读写 `CMOS` 上的指定端口，依次获取年月日时分秒等信息。至于 `CMOS` 又是如何知道时间的，这个就不在我们讨论范围了。
 
接下来 `BCD_TO_BIN` 就是 `BCD` 转换成 `BIN`，因为从 `CMOS` 上获取的这些年月日都是 `BCD` 码值，需要转换成存储在我们变量上的二进制数值。
 
最后一步 `kernel_mktime` 就是根据刚刚的那些时分秒数据，计算从 1970 年 1 月 1 日 0 时起到开机当时经过的秒数，作为开机时间，存储在 `startup_time` 这个变量里。

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
 
#pagebreak()
