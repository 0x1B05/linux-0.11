#import "../template.typ": *

= 烦死了又要重新设置一遍idt和gdt

正式进入 c 语言写的 main.c 之前的 head.s 的内容

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
caption: [head - startup_32]
)

注意到开头有个标号 `_pg_dir`，这个表示页目录，之后在设置分页机制时，页目录会存放在这里，也会覆盖这里的代码。
 
再往下连续五个 `mov` 操作，分别给 `ds`、`es`、`fs`、`gs` 这几个段寄存器赋值为 `0x10`，根据段描述符结构解析，表示这几个段寄存器的值为指向全局描述符表中的第二个段描述符，也就是数据段描述符。
 
最后 `lss` 指令相当于让 `ss:esp` 这个栈顶指针指向了 `_stack_start` 这个标号的位置。(原来的栈顶指针`0x9FF00`)

这个 `stack_start` 标号定义在了很久之后才会讲到的 `sched.c` 里。

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
caption: [head - 重新设置idt&gdt]
)

先设置了 `idt` 和 `gdt`，然后又重新执行了一遍刚刚执行过的代码。因为上面修改了 `gdt`，所以要重新设置一遍以刷新才能生效。那我们接下来就把目光放到设置 `idt` 和 `gdt` 上。

中断描述符表 `idt` 我们之前没设置过，所以这里设置具体的值，理所应当。

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
 
那这段程序的作用就是，设置了 256 个中断描述符，并且让每一个中断描述符中的中断程序例程都指向一个 `ignore_int` 的函数地址，这个是个默认的中断处理程序，之后会逐渐被各个具体的中断程序所覆盖。比如之后键盘模块会将键盘中断处理程序，覆盖过去。现在产生任何中断都会指向 `ignore_int`，也就是说现在这个阶段按键盘还不好使。
 
接下来 `setup_gdt` 就同理了。我们就直接看设置好后的新的全局描述符表(其实和我们原先设置好的 gdt 一模一样)

#figure(
```asm
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

#figure(caption: [])[#image("images/chapter8-1.png", width: 70%)]

为什么原来已经设置过一遍了，这里又要重新设置一遍，就是因为原来设置的 `gdt` 是在 `setup` 程序中，之后这个地方要被缓冲区覆盖掉，所以这里重新设置在 `head` 程序中，这块内存区域之后就不会被其他程序用到并且覆盖了。

#figure(caption: [])[#image("images/chapter8-2.png", width:70%)]

#pagebreak()
