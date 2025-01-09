#import "../template.typ": *

= 开机

== BIOS 搬运启动区代码

按下开机键的那一刻，在主板上提前写死的固件程序 BIOS 会将硬盘中启动区的 512 字节复制到内存中的 `0x7c00` 这个位置，并跳转到那个位置进行执行。

#tip("Tip")[
只要硬盘中的 0 盘 0 道 1 扇区(历史问题，CHS模式下盘片号和磁道号从0开始，扇区号从1开始)的 512 个字节的最后两个字节分别是 `0x55` 和 `0xaa`，那么 BIOS 就会认为它是个启动区。
]

#figure(caption: [])[#image("images/chapter1-1.png", width: 70%)]

此时的 BIOS 就是个代码搬运工，把 512 字节的二进制数据从硬盘搬运到了内存中而已。*作为os的开发人员，只需把操作系统最开始的那段代码，编译并存储在硬盘的 0 盘 0 道 1 扇区即可。*

Linux-0.11 的 512 字节代码即`/boot/bootsect.s`, 通过编译，这个 `bootsect.s` 会被编译成二进制文件，存放在启动区的第一扇区。

#figure(caption: [])[#image("images/chapter1-2.png", width: 40%)]

== `bootsect`
=== `0x7c00` -> `0x90000`

RTFS从这个文件的第一行代码开始:
#figure(
```asm
mov ax,0x07c0 # ax<-0x07c0
mov ds,ax     # ds<-ax<-0x07c0
```,
caption: [bootsect.s - part1]
)

#figure(caption: [])[#image("images/chapter1-3.png", width:50%)]

#tip("Tip")[
`ds` 是一个 16 位的数据段寄存器，在*内存寻址*时充当段基址的作用。就是用汇编语言写一个内存地址时，实际上仅仅是写了偏移地址，比如：

```asm
mov ax, [0x0001]
```

实际上相当于

```asm
mov ax, [ds:0x0001]
```

`ds` 是默认加上的，表示在 `ds` 这个段基址处，往后再偏移 `0x0001` 单位，将这个位置的内存数据，复制到 `ax` 寄存器中。
]

这个 `ds` 被赋值为了 `0x07c0`，由于 x86 为了让自己在 16 位这个实模式下能访问到 20 位的地址线这个历史因素，所以段基址要先左移四位。那 `0x07c0` 左移四位就是 `0x7c00`，那这就刚好和这段代码被 BIOS 加载到的内存地址 `0x7c00` 一样了。
之后再写的代码，里面访问的数据的内存地址，都要默认加上 `0x7c00`，再去内存中寻址。
#tip("Tip")[
BIOS 规定死了把操作系统代码加载到内存 `0x7c00`
#figure(caption: [])[#image("images/chapter1-4.png", width:60%)]
]

继续往下看。

#figure(
```asm
mov ax,0x07c0
mov ds,ax
mov ax,0x9000
mov es,ax   # es <- ax <- 0x9000
mov cx,#256 # cx <- 256
sub si,si   # si = si - si = 0, si寄存器清零
sub di,di   # di = di - di = 0, di寄存器清零
rep movw
```,
caption: [bootsect.s - part2]
)

经过以上几行代码，寄存器的值如图所示
#figure(caption: [])[#image("images/chapter2-1.png", width: 50%)]

给这些寄存器附上值其实就是为下一条指令服务的:

```asm
rep movw
```

其中 `rep` 表示重复执行后面的指令, 而后面的指令 `movw` 表示复制一个字（1word 16位），那其实就是不断重复地复制一个字。

- 重复执行多少次？是 `cx` 寄存器中的值，也就是 256 次。
- 从哪复制到哪？是从 `ds:si` 处复制到 `es:di` 处。
- 一次复制多少？一个字，16 位，也就是两字节。

*即：将内存地址 `0x7c00` 处开始往后的 512 Byte，原封不动复制到 `0x90000` 处。*
#figure(caption: [])[#image("images/chapter2-2.png", width: 50%)]

=== 跳转到`0x90008`

#figure(
```asm
jmpi go,0x9000
go: 
  mov ax,cs
  mov ds,ax
```,
caption: [bootsect.s - part3]
)

#tip("Tip")[
`jmpi` 是一个段间跳转指令，表示跳转到 `0x9000:go` 处执行。
]

#figure(caption: [])[#image("images/chapter2-3.png", width:50%)]

`段基址:偏移地址` 段基址仍然要先左移四位，因此就是跳转到 `0x90000 + go` 执行。

`go` 就是一个*标签*，最终编译成机器码的时候会被翻译成一个值，这个值就是 `go` 这个标签在文件内的偏移地址。假如 `mov ax,cx` 这行代码位于最终编译好后的二进制文件的 `0x08` 处，那 `go` 就等于 `0x08`，而最终 CPU 跳转到的地址就是 `0x90008` 处。

=== `go`标签：栈顶->`0x9FF00`

那接下来，就继续把目光放在 `go` 这个标签的位置。

#figure(
```asm
go: mov ax,cs
    mov ds,ax # ds <- ax <- cs
    mov es,ax # es <- ax <- cs
    mov ss,ax # ss <- ax <- cs
    mov sp,#0xFF00 # sp <- 0xFF00
```,
caption: [go标签]
)

#tip("Tip")[
`cs` 寄存器表示代码段寄存器，CPU 当前正在执行的代码在内存中的位置，就是由 `cs:ip` 这组寄存器配合指向的，其中 `cs` 是基址，`ip` 是偏移地址。
]

由于之前执行过一个段间跳转指令, 所以现在 `cs` 寄存器里的值就是 `0x9000`，`ip` 寄存器里的值是 `go` 这个标签的偏移地址。那这三个 `mov` 指令就分别给 `ds`、`es` 和 `ss` 寄存器赋值为了 `0x9000`。

- `ds` 为数据段寄存器，之前它被复制为 `0x07c0`，是因为之前的代码在 `0x7c00` 处，现在代码已经被挪到了 `0x90000` 处，所以现在自然又改赋值为 `0x9000` 了。
- `es` 是扩展段寄存器，仅仅是个扩展，先不用理它。
- `ss` 为栈段寄存器，后面要配合栈基址寄存器 `sp` 来表示此时的栈顶地址。而此时 `sp` 寄存器被赋值为了 `0xFF00` 了，所以目前的栈顶地址就是 `ss:sp` 所指向的地址 `0x9FF00` 处。

#figure(caption: [])[#image("images/chapter3-1.png", width: 60%)]

到这里操作系统的一些最基础的准备工作就做好了。操作系统在做的事情，就是给如何访问代码，如何访问数据，如何访问栈进行了一下内存的初步规划。

#figure(caption: [])[#image("images/chapter3-2.png", width: 70%)]

=== `load_setup`: 硬盘第2\~5扇区->`0x90200`

接着就来到`load_setup`
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

中断发起后，CPU 会通过这个中断号，去寻找对应的中断处理程序的入口地址，并跳转过去执行，逻辑上就相当于执行了一个函数。而 `0x13` 号中断的处理程序是 BIOS 提前写好的，是读取磁盘的相关功能的函数。

#tip("Tip")[
真正进入内核后，中断处理程序是需要自己去重新写的。此时就先用 BIOS 提前写好的程序了。可见即便是操作系统的源码，有时也需要去调用现成的函数方便自己。
]

本段代码就是将硬盘的第 2 个扇区开始，把数据加载到内存 `0x90200` 处，共加载 4 个扇区。

#figure(caption: [])[#image("images/chapter4-1.png", width: 60%)]

=== `ok_load_setup`: 硬盘第6\~255扇区->`0x10000`

如果复制成功，就跳转到 `ok_load_setup` 这个标签，如果失败，则会不断重复执行这段代码，也就是重试。那直接看成功后跳转的 `ok_load_setup` 这个标签后的代码。  省略了很多非主逻辑的代码，比如在屏幕上输出 "Loading system ..."。

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
caption: [ok_load_setup - 简化版]
)

剩下的主要代码就是把从硬盘第 6~255 扇区，加载到内存 `0x10000` ，和之前的从硬盘到内存是一个道理。

#figure(caption: [])[#image("images/chapter4-2.png",width:60%)]

至此，整个操作系统的全部代码，就已经全部从硬盘中，被搬迁到内存来了。然后通过 `jmpi 0,0x9020`，跳转到 `0x90200` 处，就是硬盘第二个扇区开始处的内容。

== `setup`
=== 操作系统的编译过程

os的编译过程，就是通过 `Makefile` 和 `build.c` 配合完成的，最终会：

1. 把 `bootsect.s` 编译成 `bootsect` 放在硬盘的 1 扇区。
2. 把 `setup.s` 编译成 `setup` 放在硬盘的 2~5 扇区。
3. 把剩下的全部代码（`head.s` 作为开头）编译成 `system` 放在硬盘的第 6~255 扇区。

#figure(caption: [])[#image("images/chapter4-3.png",width:70%)]

即将跳转到的内存中的 `0x90200` 处的代码，就是从硬盘第二个扇区开始处加载到内存的。第二个扇区的最开始处，也就是 `setup.s` 文件。

=== setup - start: 

进入`setup.s` 文件的第一部分。

#figure(
```asm
start:
    mov ax,#0x9000  ; this is done in bootsect already, but...
    mov ds,ax
    mov ah,#0x03    ; read cursor pos
    xor bh,bh
    int 0x10        ; save it in known place, con_init fetches
    mov [0],dx      ; it from 0x90000.
    ...
```,
caption: [setup.s - start1]
)

`int 0x10` 是触发 BIOS 提供的*显示服务中断处理程序*，而 `ah<-0x03` 表示显示服务里具体的`读取光标位置功能`。这个 `int 0x10` 中断程序执行完毕并返回时，`dx` 寄存器里的值表示光标的位置，具体说来其高八位 `dh` 存储了行号，低八位 `dl` 存储了列号。

#figure(caption: [])[#image("images/chapter5-1.png", width:60%)]

#tip("Tip")[
计算机在加电自检后会自动初始化到文字模式，在这种模式下，一屏幕可以显示 25 行，每行 80 个字符，也就是 80 列。
]

下一步 `mov [0],dx` 就是把这个光标位置存储在 `[0]` 这个内存地址处。`0`仅仅是偏移地址，还需要加上 `ds` 这个寄存器里存储的段基址，最终的内存地址是 `0x90000` ，这里存放着光标的位置，在后面初始化控制台的时候会用到。

`setup.s - start`剩余的代码，都是和刚刚一样的逻辑，调用一个 BIOS 中断获取信息，然后存储在内存中某个位置。

#figure(
```asm
获取内存信息。
; Get memory size (extended mem, kB)
    mov ah,#0x88
    int 0x15
    mov [2],ax
获取显卡显示模式。
; Get video-card data:
    mov ah,#0x0f
    int 0x10
    mov [4],bx      ; bh = display page
    mov [6],ax      ; al = video mode, ah = window width
检查显示方式并取参数
; check for EGA/VGA and some config parameters
    mov ah,#0x12
    mov bl,#0x10
    int 0x10
    mov [8],ax
    mov [10],bx
    mov [12],cx
获取第一块硬盘的信息。
; Get hd0 data
    mov ax,#0x0000
    mov ds,ax
    lds si,[4*0x41]
    mov ax,#INITSEG
    mov es,ax
    mov di,#0x0080
    mov cx,#0x10
    rep
    movsb
获取第二块硬盘的信息。
; Get hd1 data
    mov ax,#0x0000
    mov ds,ax
    lds si,[4*0x46]
    mov ax,#INITSEG
    mov es,ax
    mov di,#0x0090
    mov cx,#0x10
    rep
    movsb
```,
caption: [setup.s - start2]
)

需要知道最终存储在内存中的信息是什么，在什么位置，之后会用到他们。

#align(center,
  three-line-table[
  |内存地址|长度(字节)|名称|
  |-|-|-|
  |0x90000       |2  |光标位置|
  |0x90002       |2  |扩展内存数|
  |0x90004       |2  |显示页面|
  |0x90006       |1  |显示模式|
  |0x90007       |1  |字符列数|
  |0x90008       |2  |未知|
  |0x9000A       |1  |显示内存|
  |0x9000B       |1  |显示状态|
  |0x9000C       |2  |显卡特性参数|
  |0x9000E       |1  |屏幕行数|
  |0x9000F       |1  |屏幕列数|
  |0x90080       |16 |硬盘1参数表|
  |0x90090       |16 |硬盘2参数表|
  |0x901FC       |2  |根设备号|
  ]
)

#tip("Tip")[
很快回进入 c 语言的代码，虽然汇编和 c 语言也可以用变量的形式进行数据传递，但这需要编译器在链接时做一些额外的工作，所以这么多数据更方便的还是双方共同约定一个内存地址，我往这里存，你从这里取。
]

=== `isdisk1` & `do_move`

#figure(
```asm
is_disk1:
; now we want to move to protected mode ...
    cli ; no interrupts allowed !
; first we move the system to it's rightful place
    mov ax,#0x0000
    cld ; 'direction'=0, movs moves forward
; first we move the system to it's rightful place
    mov ax,#0x0000
    cld         ; 'direction'=0, movs moves forward
do_move:
    mov es,ax       ; destination segment
    add ax,#0x1000
    cmp ax,#0x9000
    jz  end_move
    mov ds,ax       ; source segment
    sub di,di
    sub si,si
    mov cx,#0x8000
    rep movsw
    jmp do_move
; then we load the segment descriptors
```,
caption: [isdisk1 & do_move]
)
第一行 `cli`，表示关中断。因为后面要把原本 BIOS 的中断向量表用操作系统的中断向量表给覆盖掉，所以这个时候是不允许中断进来的。

后面的 `rep movsw` ，也是内存复制，最终的结果是，把内存地址 `0x10000` 处开始往后一直到 `0x90000` 的内容，复制到内存的最开始的 `0x0`。

#figure(caption: [])[#image("images/chapter5-2.png", width:60%)]

重新梳理一下此时的内存布局。

#figure(caption: [])[#image("images/chapter5-3.png",width:30%)]

=== `end_move`
==== 更新idtr和gdtr

接下来就要进行模式的转换了，需要从现在的 16 位的实模式转变为之后 32 位的保护模式。这是 x86 的历史包袱问题，现在的 CPU 几乎都是支持 32 位模式甚至 64 位模式了，很少有还仅仅停留在 16 位的实模式下的 CPU。所以要为了这个历史包袱，写一段模式转换的代码，如果 Intel CPU 被重新设计而不用考虑兼容性，那么今天的代码将会减少很多甚至不复存在。

#figure(
```asm
end_move:
    ...
    lidt  idt_48      ; load idt with 0,0
    lgdt  gdt_48      ; load gdt with whatever appropriate
```,
caption: [end_move - part1]
)

要理解这两条指令，就涉及到实模式和保护模式的第一个区别了。现在还处于实模式下, 当 CPU 切换到保护模式后，同样的代码，内存地址的计算方式与原先实模式并不一样:
- 实模式：段基址左移四位，再加上偏移地址
- 保护模式：`ds` 寄存器里存储的值，在实模式下叫做段基址，在保护模式下叫段选择子。段选择子里存储着段描述符的索引。
  #figure(caption: [])[#image("images/chapter6-1.png", width: 40%)]
  通过段描述符索引，可以从全局描述符表 `gdt` 中找到一个段描述符，段描述符里存储着段基址。
  #figure(caption: [])[#image("images/chapter6-2.png",width:70%)]
  段基址取出来，再和偏移地址相加，就得到了物理地址，整个过程如下。
  #figure(caption: [])[#image("images/chapter6-3.png",width:55%)]

段寄存器（比如 `ds`、`ss`、`cs`）里存储的是段选择子，段选择子去全局描述符表中寻找段描述符，从中取出段基址。由操作系统把全局描述符表（`gdt`）在内存中这个位置信息存储在一个叫 `gdtr` 的寄存器中。

#figure(caption: [gdtr 寄存器结构])[#image("images/chapter6-4.png", width:60%)]

`lidt` 就表示把后面的值（`idt_48`）放在 `idtr` 寄存器中，`idt_48` 标签。`lgdt`同理。
- `idtr` 寄存器，存储的是中断描述符表的位置。中断描述符表是用来在发生中断时，CPU 拿着中断号去中断描述符表中寻找中断处理程序的地址，找到后就跳到相应的中断程序中去执行。
- `gdtr` 寄存器，存储的是全局描述表的位置。

===== `idt_48` & `gdt_48`

#figure(
```asm
idt_48:
    .word   0     ; idt limit=0
    .word   0,0   ; idt base=0L
gdt_48:
    .word   0x800       ; gdt limit=2048, 256 GDT entries
    .word   512+gdt,0x9 ; gdt base = 0X9xxxx
```,
caption: [idt_48 & gdt_48]
)

可以看到这个标签位置处表示一个 48 位的数据，其中高 32 位存储着的正是全局描述符表 `gdt` 的内存地址`0x90200 + gdt`, `gdt` 是个标签，表示在本文件内的偏移量，而本文件是 `setup.s`，编译后是放在 `0x90200` 这个内存地址的

#figure(caption: [])[#image("images/chapter6-5.png",width:35%)]

===== `gdt`

`gdt` 这个标签处，就是全局描述符表在内存中的真正数据了。

#figure(
```asm
gdt:
    .word   0,0,0,0     ; dummy

    .word   0x07FF      ; 8Mb - limit=2047 (2048*4096=8Mb)
    .word   0x0000      ; base address=0
    .word   0x9A00      ; code read/exec
    .word   0x00C0      ; granularity=4096, 386

    .word   0x07FF      ; 8Mb - limit=2047 (2048*4096=8Mb)
    .word   0x0000      ; base address=0
    .word   0x9200      ; data read/write
    .word   0x00C0      ; granularity=4096, 386
```,
caption: [setup - gdt]
)

根据刚刚的段描述符格式
  #figure(caption: [])[#image("images/chapter6-2.png",width:70%)]

可以看出目前全局描述符表有三个段描述符: 
- 第一个为空
- 第二个是代码段描述符（`type=code`）
- 第三个是数据段描述符（`type=data`）

第二个和第三个段描述符的段基址都是 0，也就是之后在逻辑地址转换物理地址的时候，通过段选择子查找到无论是代码段还是数据段，取出的段基址都是 0，那么物理地址将直接等于程序员给出的逻辑地址（准确说是逻辑地址中的偏移地址）。

#figure(caption: [])[#image("images/chapter6-6.png", width: 25%)]

目前的内存布局。

#figure(caption: [])[#image("images/chapter6-7.png", width: 60%)]

==== RTFM

保护模式下逻辑地址到线性地址（不开启分页时就是物理地址）的转化(Intel 手册： Volume 3 Chapter 3.4 Logical And Linear Addresses)：
#figure(caption: [])[#image("images/chapter6-8.png", width:80%)]

段描述符结构和详细说明(Intel 手册： Volume 3 Chapter 3.4.5 Segment Descriptors)：
#figure(caption: [])[#image("images/chapter6-9.png", width:80%)]

==== 进入保护模式

接着往下看:

#figure(
```asm
mov al,#0xD1        ; command write
out #0x64,al
mov al,#0xDF        ; A20 on
out #0x60,al
```,
caption: [end_move - part2]
)

#tip("Tip")[
  #h(2em)这一步就是为了突破地址信号线 20 位的宽度，变成 32 位可用。这是由于 8086 CPU 只有 20 位的地址线，所以如果程序给出 21 位的内存地址数据，那多出的一位就被忽略了，比如如果经过计算得出一个内存地址为 `1 0000 00000000 00000000`, 那实际上内存地址相当于 0，因为高位的那个 1 被忽略了，地方不够。
 
当 CPU 到了 32 位时代之后，由于要考虑兼容性，还必须保持一个只能用 20 位地址线的模式，所以如果你不手动开启的话，即使地址线已经有 32 位了，仍然会限制只能使用其中的 20 位。
]

#figure(
```asm
; well, that went ok, I hope. Now we have to reprogram the interrupts :-(
; we put them right after the intel-reserved hardware interrupts, at
; int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
; messed this up with the original PC, and they haven't been able to
; rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
; which is used for the internal hardware interrupts as well. We just
; have to reprogram the 8259's, and it isn't fun.

    mov al,#0x11        ; initialization sequence
    out #0x20,al        ; send it to 8259A-1
    .word   0x00eb,0x00eb       ; jmp $+2, jmp $+2
    out #0xA0,al        ; and to 8259A-2
    .word   0x00eb,0x00eb
    mov al,#0x20        ; start of hardware int's (0x20)
    out #0x21,al
    .word   0x00eb,0x00eb
    mov al,#0x28        ; start of hardware int's 2 (0x28)
    out #0xA1,al
    .word   0x00eb,0x00eb
    mov al,#0x04        ; 8259-1 is master
    out #0x21,al
    .word   0x00eb,0x00eb
    mov al,#0x02        ; 8259-2 is slave
    out #0xA1,al
    .word   0x00eb,0x00eb
    mov al,#0x01        ; 8086 mode for both
    out #0x21,al
    .word   0x00eb,0x00eb
    out #0xA1,al
    .word   0x00eb,0x00eb
    mov al,#0xFF        ; mask off all interrupts for now
    out #0x21,al
    .word   0x00eb,0x00eb
    out #0xA1,al
```,
caption: [setup - 对可编程中断控制器 8259 芯片进行的编程]
)

因为中断号是不能冲突的， Intel 把 0 到 0x19 号中断都作为保留中断，比如 0 号中断就规定为除零异常，软件自定义的中断都应该放在这之后，但是 IBM 在原 PC 机中搞砸了，跟保留中断号发生了冲突，以后也没有纠正过来，所以得重新对其进行编程，不得不做，却又一点意思也没有。

不必在意，只要知道重新编程之后，8259 这个芯片的引脚与中断号的对应关系，变成了如下的样子就好。

#align(center, 
three-line-table[
|PIC 请求号|中断号|用途|
|-|-|-|
|IRQ0|  0x20|   时钟中断|
|IRQ1|  0x21|   键盘中断|
|IRQ2|  0x22|   接连从芯片|
|IRQ3|  0x23|   串口2|
|IRQ4|  0x24|   串口1|
|IRQ5|  0x25|   并口2|
|IRQ6|  0x26|   软盘驱动器|
|IRQ7|  0x27|   并口1|
|IRQ8|  0x28|   实时钟中断|
|IRQ9|  0x29|   保留|
|IRQ10| 0x2a|   保留|
|IRQ11| 0x2b|   保留|
|IRQ12| 0x2c|   鼠标中断|
|IRQ13| 0x2d|   数学协处理器|
|IRQ14| 0x2e|   硬盘中断|
|IRQ15| 0x2f|   保留|
]
)

接下来的一步，就是真正切换模式的一步了

#figure(
```asm
mov ax,#0x0001  ; protected mode (PE) bit
lmsw ax      ; This is it;
jmpi 0,8     ; jmp offset 0 of segment 8 (cs)
```,
caption: [setup - 切换模式真正的一步]
)

前两行，将 `cr0` 这个寄存器的位 `0` 置 `1`，模式就从实模式切换到保护模式了。

#figure(caption: [])[#image("images/chapter7-3.png", width:70%)]

再往后，又是一个段间跳转指令 `jmpi`，后面的 `8` 表示 `cs`（代码段寄存器）的值，`0` 表示偏移地址。请注意，此时已经是保护模式了，之前也说过，保护模式下内存寻址方式变了，段寄存器里的值被当做段选择子。

`8` 用二进制表示就是 `00000,0000,0000,1000`, 对照上面段选择子的结构，可以知道描述符索引值是 `1`，也就是要去全局描述符表（`gdt`）中找第一项段描述符。

记得(段基址都为0)
```
gdt[0] <- null
gdt[1] <- 代码段描述符 r-x
gdt[2] <- 数据段描述符 rw-
```

所以，这里取的就是这个代码段描述符，段基址是 `0`，偏移也是 `0`，那加一块就还是 `0` 咯，所以最终这个跳转指令，就是跳转到内存地址的 `0` 地址处，开始执行。

零地址处操作系统的全部代码。

#figure(caption: [])[#image("images/chapter7-4.png", width:70%)]

就是操作系统全部代码的 `system` 这个大模块，`system` 模块怎么生成的呢？由 `Makefile` 文件可知，是由 `head.s` 和 `main.c` 以及其余各模块的操作系统代码合并来的，可以理解为操作系统的全部核心代码编译后的结果。

#figure(
```make
tools/system: boot/head.o init/main.o \
    $(ARCHIVES) $(DRIVERS) $(MATH) $(LIBS)
    $(LD) $(LDFLAGS) boot/head.o init/main.o \
    $(ARCHIVES) \
    $(DRIVERS) \
    $(MATH) \
    $(LIBS) \
    -o tools/system > System.map
```,
caption: [makefile - system]
)

== `system`

=== `head` - `startup_32`: 重新设置一遍idt和gdt

进入 head.s 的内容

#figure(
```asm
_pg_dir:
_startup_32:
    mov eax,0x10
    mov ds,ax # ds <- 0x10
    mov es,ax # es <- 0x10
    mov fs,ax # fs <- 0x10
    mov gs,ax # gs <- 0x10
    lss esp,_stack_start
```,
caption: [head - startup_32 1]
)

开头有个标号 `_pg_dir`，表示页目录，之后在设置分页机制时，页目录会存放在这里，也会覆盖这里的代码。
 
连续五个 `mov` 操作，分别给 `ds`、`es`、`fs`、`gs` 这几个段寄存器赋值为 `0x10`，根据段描述符结构解析，表示这几个段寄存器的值为指向全局描述符表中的第二个段描述符，即*数据段描述符*。
 
`lss` 指令相当于让 `ss:esp` 这个栈顶指针指向了 `_stack_start` 这个标号的位置。(原来的栈顶指针`0x9FF00`)

==== `stack_start`
这个 `stack_start` 标号定义在了后面的 `sched.c` 里。

#figure(
```c
long user_stack[4096 >> 2];

struct
{
  long *a;
  short b;
}
stack_start = {&user_stack[4096 >> 2], 0x10};
```,
caption: [sched - stack_start]
)

`stack_start` 结构中的高位 8 字节是 `0x10`，将会赋值给 `ss` 栈段寄存器，低位 16 字节是 `user_stack` 这个数组的最后一个元素的地址值，将其赋值给 `esp` 寄存器。 赋值给 `ss` 的 `0x10` 仍然按照保护模式下的段选择子去解读，其指向的是全局描述符表中的第二个段描述符（数据段描述符），段基址是 `0`。

赋值给 `esp` 寄存器的就是 `user_stack` 数组的最后一个元素的内存地址值，那最终的栈顶地址，也指向了这里（`user_stack + 0`），后面的压栈操作，就是往这个新的栈顶地址处压咯。

==== `setup_idt` & `setup_gdt`: 填idt和gdt表
继续往下看

#figure(
```asm
call setup_idt ;设置中断描述符表
call setup_gdt ;设置全局描述符表
mov eax,10h
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
lss esp,_stack_start
```,
caption: [head - startup_32 2]
)

先设置了 `idt` 和 `gdt`，然后又重新执行了一遍刚刚执行过的代码。因为上面修改了 `gdt`，所以要重新设置一遍以刷新才能生效。那接下来就把目光放到设置 `idt` 和 `gdt` 上。

中断描述符表 `idt` 里的内容先前为空，所以这里设置具体的值。

#figure(
```asm
setup_idt:
    lea edx,ignore_int
    mov eax,00080000h
    mov ax,dx
    mov dx,8E00h
    lea edi,_idt
    mov ecx,256
rp_sidt:
    mov [edi],eax
    mov [edi+4],edx
    add edi,8
    dec ecx
    jne rp_sidt
    lidt fword ptr idt_descr
    ret

idt_descr:
    dw 256*8-1
    dd _idt

_idt:
    DQ 256 dup(0)
```,
caption: [head - setup_idt]
)

中断描述符表 `idt` 里面存储着一个个中断描述符，每一个中断号就对应着一个中断描述符，而中断描述符里面存储着主要是中断程序的地址，这样一个中断号过来后，CPU 就会自动寻找相应的中断程序，然后去执行它。
 
那这段代码的作用即，设置了 256 个中断描述符，并且让每一个中断描述符中的中断程序例程都指向一个 `ignore_int` 的函数地址(默认的中断处理程序)，之后会逐渐被各个具体的中断程序所覆盖。比如之后键盘模块会将键盘中断处理程序，覆盖过去。现在产生任何中断都会指向 `ignore_int`，也就是说现在这个阶段按键盘还不好使。
 
接下来 `setup_gdt` 同理了。直接看设置好后的新的全局描述符表(其实和原先的 `gdt` 一模一样)

#figure(
```asm
setup_gdt:
    lgdt gdt_descr
    ret
gdt_descr:
    .word 256*8-1 ; so does gdt (not that that's any
    .long gdt     ; magic number, but it works for me :^)
    .align 8
_gdt:
    DQ 0000000000000000h    ;/* NULL descriptor */
    DQ 00c09a0000000fffh    ;/* 16Mb */
    DQ 00c0920000000fffh    ;/* 16Mb */
    DQ 0000000000000000h    ;/* TEMPORARY - don't use */
    DQ 252 dup(0)
```,
caption: [head - gdt]
)

也是有代码段描述符和数据段描述符，然后第四项系统段描述符并没有用到。最后还留了 252 项的空间，这些空间后面会用来放置任务状态段描述符 `TSS` 和局部描述符 `LDT`。

#figure(caption: [])[#image("images/chapter8-1.png", width: 60%)]

为什么原来已经设置过一遍了，这里又要重新设置一遍，就是因为原来的 `gdt` 在 `setup` 程序中，之后这块内存要被缓冲区覆盖掉，所以重新设置在 `head` 程序中，这块内存区域之后不会再被其他程序用到并且覆盖了。

#figure(caption: [])[#image("images/chapter8-2.png", width:60%)]

=== `after_page_tables`: 开启分页前把`main`压栈

#figure(
```asm
startup_32:
  ...
  jmp after_page_tables
after_page_tables:
    pushl $0      # These are the parameters to main :-)
    pushl $0
    pushl $0
    pushl $L6     # return address for main, if it decides to.
    pushl $main
    jmp setup_paging
L6:
    jmp L6
```,
caption: [head - after_page_tables]
)

=== `setup_paging`: 开启分页

在没有开启分页机制时，由程序员给出的逻辑地址，需要先通过分段机制转换成物理地址。

在开启分页机制后，逻辑地址仍然要先通过分段机制进行转换，只不过转换后不再是最终的物理地址，而是线性地址，然后再通过一次分页机制转换，得到最终的物理地址。

#figure(caption: [])[#image("images/chapter9-1.png", width:35%)]

Linux-0.11采用二级页表：
#figure(caption: [])[#image("images/chapter9-2.png", width: 70%)]

计算机的一个硬件 MMU(内存管理单元，有时也叫 PMMU，分页内存管理单元)负责将虚拟地址转换为物理地址。
 
整个过程os不用操心，os只需要提供页目录表和页表即可，第一级叫页目录表 `PDE`，第二级叫页表 `PTE`。页目录项/页表项的结构如下。

#figure(caption: [页目录项/页表项结构])[#image("images/chapter9-3.png", width: 80%)]

开启分页机制的开关，其实就是更改 `cr0` 寄存器中的一位即可（31 位）
#figure(caption: [cr0 寄存器])[#image("images/chapter9-4.png", width: 80%)]

此后，MMU 就可以进行分页的转换了。以后指令中的内存地址（程序员提供的逻辑地址），就全部要先经过分段机制的转换，再通过分页机制的转换，才能最终变成物理地址。

#figure(
```asm
setup_paging:
    mov ecx,1024*5
    xor eax,eax
    xor edi,edi
    pushf
    cld
    rep stosd
    mov eax,_pg_dir
    mov [eax],pg0+7
    mov [eax+4],pg1+7
    mov [eax+8],pg2+7
    mov [eax+12],pg3+7
    mov edi,pg3+4092
    mov eax,00fff007h
    std
L3: stosd
    sub eax,00001000h
    jge L3
    popf
    xor eax,eax
    mov cr3,eax
    mov eax,cr0
    or  eax,80000000h
    mov cr0,eax
    ret
```,
caption: [head - setup_paging]
)

这段代码，就是把页表和页目录表在内存中写好，之后开启 `cr0` 寄存器的分页开关。

当时 Linux-0.11 认为，总共可以使用的内存不会超过 `16M`(2^24B)。 而按照当前的页目录表和页表这种机制，1 个页目录表最多包含 1024 个页目录项（也就是 2^10 个页表），1 个页表最多包含 1024 个页表项（也就是 1024 个页），1 页为 4KB（2^12），因此，16M 的地址空间可以用 1 个页目录表 + 4 个页表搞定。
 
4（页表数）* 1024（页表项数） * 4KB（一页大小）= 16MB
 
所以，`setup_paging`就是，将页目录表(`_pg_dir`)放在内存地址的最开头，之后紧挨着这个页目录表，放置 4 个页表，代码里也有这四个页表的标签项。

#figure(
```asm
.org 0x1000 pg0:
.org 0x2000 pg1:
.org 0x3000 pg2:
.org 0x4000 pg3:
.org 0x5000
```,
caption: [head - 页表标签项]
)

最终将页目录表和页表填写好数值，来覆盖整个 16MB 的内存。随后，开启分页机制。此时内存中的页表相关的布局如下。

#figure(caption: [])[#image("images/chapter9-5.png", width:30%)]

这些页目录表和页表放到了整个内存布局中最开头的位置，就是覆盖了开头的 `system` 代码了，不过被覆盖的 system 代码已经执行过了，所以没有影响。

同时，如 `idt` 和 `gdt` 一样，也需要通过一个寄存器告诉 CPU 把这些页表放在了哪里。在这里就是告诉 `cr3` 寄存器，`0` 地址处就是页目录表，再通过页目录表可以找到所有的页表

```
xor eax,eax
mov cr3,eax
```

至此后，整个内存布局如下
#figure(caption: [])[#image("images/chpater9-6.png", width:60%)]

具体页表设置好后，映射的内存就要看页表的具体数据了:
#figure(
```asm
setup_paging:
    ...
    mov eax,_pg_dir
    mov [eax],pg0+7 # [eax] <- pg0+7(0x00001007)
    mov [eax+4],pg1+7
    mov [eax+8],pg2+7
    mov [eax+12],pg3+7
    mov edi,pg3+4092
    mov eax,00fff007h
    std
L3: stosd
    sub eax, 1000h
    jpe L3
    ...
```,
caption: [head - setup_paging]
)

对照刚刚的页目录表与页表结构看

#figure(caption: [])[#image("images/chapter9-3.png", width: 80%)]

前五行表示，页目录表的前 4 个页目录项，分别指向 4 个页表。比如页目录项中的第一项 `[eax] <- pg0+7`，也就是 `0x00001007`，根据页目录项的格式，表示页表地址为 `0x1000`，页属性为 `0x07` 表示该页存在、用户可读写。

后面几行表示，填充 4 个页表的每一项，一共 4\*1024=4096 项，依次映射到内存的前 16MB 空间。

#figure(caption: [])[#image("images/chapter9-2.png", width: 70%)]

#definition("Definition")[
*线性地址*：通过分段机制，将逻辑地址转换后的地址，叫做线性地址。而这个线性地址是有个范围的，这个范围就叫做线性地址空间，32 位模式下，线性地址空间就是 4G。
]

=== RTFM

逻辑地址-线性地址-物理地址的转换: Intel 3A Chapter 3 Protected-Mode Memory Management
#figure(caption: [])[#image("images/chapter9-8.png", width: 80%)]
#figure(caption: [])[#image("images/chapter9-7.png", width: 80%)]
页目录表和页表的具体结构: Intel 3A Chapter 4.3 32-bit paging
#figure(caption: [])[#image("images/chapter9-9.png", width: 80%)]
#figure(caption: [])[#image("images/chapter9-10.png", width: 80%)]

== `setup_paging`返回: 进入`main`函数前的最后一跃

#figure(
```asm
after_page_tables:
    push 0
    push 0
    push 0
    push L6
    push _main
    jmp setup_paging
...
setup_paging:
    ...
    ret
```,
caption: [head - 跳转main]
)

#figure(caption: [])[#image("images/chapter10-1.png", width: 30%)]

#h(2em)`setup_paging` 最后一个指令是 `ret`，形象地说它叫返回指令，把栈顶的元素值当做返回地址，CPU会跳转去那里执行。

再具体说是，把 `esp` 寄存器（栈顶地址）所指向的内存处的值，赋值给 `eip` 寄存器，而 `cs:eip` 就是 CPU 要执行的下一条指令的地址。而此时栈顶刚好是 `main.c` 里写的 `main` 函数的内存地址，是刚刚特意压入栈的，所以 CPU 就跳过来了。

压入栈的 `L6` 是用作当 `main` 函数返回时的跳转地址，但由于在操作系统层面的设计上，`main` 是绝对不会返回的，所以也就没用了。而其他的三个压栈的 `0`，本意是作为 `main` 函数的参数，但实际上似乎也没有用到。

总结进入内核前的准备工作：
#figure(caption: [])[#image("images/chapter10-2.png", width: 50%)]
内存布局
#figure(caption: [])[#image("images/chapter10-3.png", width: 60%)]

=== RTFM

有关 `call` 和 `ret` 指令： Intel 1 Chapter 6.4 CALLING PROCEDURES USING CALL AND RET
#figure(caption: [])[#image("images/chapter10-4.png", width: 80%)]

以及改变段基址的 `far call` 和 `far ret`：
#figure(caption: [])[#image("images/chapter10-5.png", width: 80%)]

压栈和出栈的具体过程图示：
#figure(caption: [])[#image("images/chapter10-6.png", width: 80%)]

本文就是左边的那一套，把 `main` 函数地址值当做 `Calling EIP` 压入栈，仿佛是执行了 `call` 指令调用了一个函数一样，然后 `ret` 的时候就把栈顶的那个 `Calling EIP` 也就是 `main` 函数地址弹出栈，存入 `EIP` 寄存器，这样 CPU 就相当于“返回”到了 `main` 函数开始执行。

#pagebreak()
