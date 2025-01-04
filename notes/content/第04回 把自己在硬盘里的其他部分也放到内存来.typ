#import "../template.typ": *

= 把自己在硬盘里的其他部分也放到内存来

#figure(
```asm
load_setup:
    mov dx,#0x0000      ; drive 0, head 0
    mov cx,#0x0002      ; sector 2, track 0
    mov bx,#0x0200      ; address = 512, in 0x9000
    mov ax,#0x0200+4    ; service 2, nr of sectors
    int 0x13            ; read it
    jnc ok_load_setup       ; ok - continue
    mov dx,#0x0000
    mov ax,#0x0000      ; reset the diskette
    int 0x13
    jmp load_setup

ok_load_setup:
    ...
```,
caption: [load_setup]
)

`int 0x13` 表示发起 `0x13` 号中断，这条指令上面给 `dx`、`cx`、`bx`、`ax` 赋值都是作为这个中断程序的参数。

中断发起后，CPU 会通过这个中断号，去寻找对应的中断处理程序的入口地址，并跳转过去执行，逻辑上就相当于执行了一个函数。而 `0x13` 号中断的处理程序是 BIOS 提前给我们写好的，是读取磁盘的相关功能的函数。
#tip("Tip")[
真正进入操作系统内核后，中断处理程序是需要我们自己去重新写的。此时为了方便就先用 BIOS 提前给我们写好的程序了。可见即便是操作系统的源码，有时也需要去调用现成的函数方便自己。
]

本段代码就是将硬盘的第 2 个扇区开始，把数据加载到内存 `0x90200` 处，共加载 4 个扇区。
#figure(caption: [])[#image("images/chapter4-1.png", width: 60%)]

如果复制成功，就跳转到 `ok_load_setup` 这个标签，如果失败，则会不断重复执行这段代码，也就是重试。那我们直接看成功后跳转的 `ok_load_setup` 这个标签后的代码。

#figure(
```asm
ok_load_setup:
    ...
    mov ax,#0x1000
    mov es,ax       ; segment of 0x10000
    call read_it
    ...
    jmpi 0,0x9020
```,
caption: [ok_load_setup]
)

#tip("Tip")[
  省略了很多非主逻辑的代码，比如在屏幕上输出 "Loading system ..."。
]

剩下的主要代码就是把从硬盘第 6 个扇区开始往后的 240 个扇区，加载到内存 `0x10000` 处，和之前的从硬盘捣腾到内存是一个道理。

#figure(caption: [])[#image("images/chapter4-2.png",width:60%)]

至此，整个操作系统的全部代码，就已经全部从硬盘中，被搬迁到内存来了。

然后又通过一个熟悉的段间跳转指令 `jmpi 0,0x9020`，跳转到 `0x90200` 处，就是硬盘第二个扇区开始处的内容。

把整个操作系统的编译过程说下。整个编译过程，就是通过 `Makefile` 和 `build.c` 配合完成的，最终会：

1. 把 `bootsect.s` 编译成 `bootsect` 放在硬盘的 1 扇区。
2. 把 `setup.s` 编译成 `setup` 放在硬盘的 2~5 扇区。
3. 把剩下的全部代码（`head.s` 作为开头）编译成 `system` 放在硬盘的随后 240 个扇区。

#figure(caption: [])[#image("images/chapter4-3.png",width:80%)]

我们即将跳转到的内存中的 0x90200 处的代码，就是从硬盘第二个扇区开始处加载到内存的。第二个扇区的最开始处，那也就是 `setup.s` 文件的第一行代码咯。

#pagebreak()
