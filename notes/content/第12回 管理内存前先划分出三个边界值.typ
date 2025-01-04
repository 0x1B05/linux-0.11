#import "../template.typ": *

= 管理内存前先划分出三个边界值(`mem_init`)

首先，`ROOT_DEV` 为系统的根文件设备号，`drive_info` 为之前 `setup.s` 程序获取并存储在内存 `0x90000` 处的设备信息，等之后用到了再说。

#figure(
```c
void main(void) {
    ...
    memory_end = (1<<20) + (EXT_MEM_K<<10);
    memory_end &= 0xfffff000;
    if (memory_end > 16*1024*1024)
        memory_end = 16*1024*1024;
    if (memory_end > 12*1024*1024) 
        buffer_memory_end = 4*1024*1024;
    else if (memory_end > 6*1024*1024)
        buffer_memory_end = 2*1024*1024;
    else
        buffer_memory_end = 1*1024*1024;
    main_memory_start = buffer_memory_end;
    ...
}
```,
caption: [main - memory]
)
#h(2em)这一坨代码虽然很乱，但仔细看就知道它只是为了计算出三个变量： `main_memory_start`, `memory_end`, `buffer_memory_end`

而观察最后一行代码发现，其实两个变量是相等的，所以其实仅仅计算出了两个变量：
`main_memory_start`, `memory_end`

其实就是一堆 `if else` 判断而已，判断的标准都是 `memory_end` 也就是内存最大值的大小，而这个内存最大值由第一行代码可以看出，是等于 `1M + 扩展内存大小`。就只是针对不同的内存大小，设置不同的边界值罢了

那么如果内存为 8M 大小，`memory_end` 就是 `8 * 1024 * 1024`, 也就只会走倒数第二个分支，那么 `buffer_memory_end` 就为 `2 * 1024 * 1024`, 那么 `main_memory_start` 也为 `2 * 1024 * 1024`
#figure(caption: [])[#image("images/chapter12-1.png", width: 40%)]

其实就是定了三个箭头所指向的地址的三个边界变量，具体主内存区是如何管理和分配的，要看下面代码

#figure(
```c
void main(void) {
    ...
    mem_init(main_memory_start, memory_end);
    ...
}
```,
caption: [main - mem_init]
)

而缓冲区是如何管理和分配的，就要看

#figure(
```c
void main(void) {
    ...
    buffer_init(buffer_memory_end);
    ...
}
```,
caption: [main - buffer_init]
)

#pagebreak()
