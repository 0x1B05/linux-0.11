#import "../template.typ": *

= 六行代码就进入了保护模式

#figure(caption: [])[#image("images/chapter7-1.png", width:70%)]

此时我们的内存布局变成了这个样子。

#figure(caption: [])[#image("images/chapter7-2.png", width:70%)]

接着往下看:

#figure(
```asm
mov al,#0xD1        ; command write
out #0x64,al
mov al,#0xDF        ; A20 on
out #0x60,al
```,
caption: [setup - 打开A20地址线]
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

因为中断号是不能冲突的， Intel 把 0 到 0x19 号中断都作为保留中断，比如 0 号中断就规定为除零异常，软件自定义的中断都应该放在这之后，但是 IBM 在原 PC 机中搞砸了，跟保留中断号发生了冲突，以后也没有纠正过来，所以我们得重新对其进行编程，不得不做，却又一点意思也没有。

我们也不必在意，只要知道重新编程之后，8259 这个芯片的引脚与中断号的对应关系，变成了如下的样子就好。

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

我们记得(段基址都为0)
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

#pagebreak()
