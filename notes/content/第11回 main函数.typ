#import "../template.typ": *

= 整个操作系统就 20 几行代码.typ
#figure(
```c
void main(void) {
    ROOT_DEV = ORIG_ROOT_DEV;
    drive_info = DRIVE_INFO;
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
    mem_init(main_memory_start,memory_end);
    trap_init();
    blk_dev_init();
    chr_dev_init();
    tty_init();
    time_init();
    sched_init();
    buffer_init(buffer_memory_end);
    hd_init();
    floppy_init();
    sti();
    move_to_user_mode();
    if (!fork()) {
        init();
    }
    for(;;) pause();
}
```,
caption: [main]
)

第一部分是一些参数的取值和计算。包括根设备 `ROOT_DEV`，之前在汇编语言中获取的各个设备的参数信息 `drive_info`，以及通过计算得到的内存边界 `main_memory_start`, `main_memory_end`, `buffer_memory_start`, `buffer_memory_end`

#figure(
```c
void main(void) {
    ROOT_DEV = ORIG_ROOT_DEV;
    drive_info = DRIVE_INFO;
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
caption: [main - part1]
)

#tip("Tip")[
设备参数信息都是由 setup.s 这个汇编程序调用 BIOS 中断获取的各个设备的信息，并保存在约定好的内存地址 0x90000 处。
]

第二部分是各种初始化 init 操作。包括内存初始化 `mem_init`，中断初始化 `trap_init`、进程调度初始化 `sched_init` 等等。

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
    hd_init();
    floppy_init();
    ...
}
```,
caption: [main - part2]
)

 
第三部分是切换到用户态模式，并在一个新的进程中做一个最终的初始化 `init`。这个 `init` 函数里会创建出一个进程，设置终端的标准 IO，并且再创建出一个执行 shell 程序的进程用来接受用户的命令，到这里其实就出现了我们熟悉的shell画面。

#figure(
```c
void main(void) {
    ...
    sti();
    move_to_user_mode();
    if (!fork()) {
        init();
    }
    ...
}
```,
caption: [main - part3]
)

第四部分是个死循环，如果没有任何任务可以运行，操作系统会一直陷入这个死循环无法自拔。

#figure(
```c
void main(void) {
    ...
    for(;;) pause();
}
```,
caption: [main - part4]
)

要牢记内存布局图。
#figure(caption: [])[#image("images/chapter11-1.png", width: 70%)]
#pagebreak()
