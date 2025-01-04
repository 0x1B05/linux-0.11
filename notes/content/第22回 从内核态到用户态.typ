#import "../template.typ": *

= 从内核态到用户态

就重点讲这第一句代码，`move_to_user_mode`

== 内核态与用户态的本质-特权级
从一个最大的视角来看，这一切都源于 CPU 的保护机制。CPU 为了配合操作系统完成保护机制这一特性，分别设计了分段保护机制与分页保护机制。
#figure(caption: [])[#image("images/chapter22-1.png", width: 80%)]
有关特权级的保护，实际上属于分段保护机制的一种。我们目前正在执行的代码地址，是通过 CPU 中的两个寄存器 `cs : eip` 指向的，`cs` 寄存器是代码段寄存器，里面存着的是段选择子
#figure(caption: [])[#image("images/chapter22-2.png", width: 60%)]

这里面的低端两位，此时表示 `CPL`，也就是当前所处的特权级，假如 `CS` 寄存器的后两位为`3`(`11b`)，就表示是当前处理器处于用户态这个特权级。

假如此时要跳转到另一处内存地址执行，在最终的汇编指令层面无非就是 `jmp`、`call` 和中断。以 `jmp` 跳转为例。
- 如果是短跳转，也就是直接 `jmp xxx`，那不涉及到段的变换，也就没有特权级检查这回事。
- 如果是长跳转，也就是 `jmp yyy : xxx`，这里的 `yyy` 就是另一个要跳转到的段的段选择子结构。这个结构仍然是一样的段选择子结构，只不过这里的低端两位，表示 `RPL`，也就是请求特权级，表示想请求的特权级是什么。同时，CPU 会拿这个段选择子去全局描述符表中寻找段描述符，从中找到段基址。
  - 段描述符里面有个 `DPL`，这表示目标代码段特权级，也就是即将要跳转过去的那个段的特权级。#figure(caption: [])[#image("images/chapter22-3.png", width: 90%)] 

总结：
#figure(caption: [])[#image("images/chapter22-4.png", width: 70%)] 

绝大多数情况下，要求 *CPL 必须等于 DPL*，才会跳转成功，否则就会报错。即当前代码所处段的特权级，必须要等于要跳转过去的代码所处的段的特权级，那就只能用户态往用户态跳，内核态往内核态跳。

这只是代码段跳转时所做的特权级检查，还有访问内存数据时也会有数据段的特权级检查。最终的效果是，处于*内核态的代码可以访问任何特权级的数据段，处于用户态的代码则只可以访问用户态的数据段*，这也就实现了内存数据读写的保护。

== 特权级转换的方式

我们现在处于内核态，要怎么样才能跳转到用户态呢？Intel 设计了好多种特权级转换的方式，中断和中断返回就是其中的一种。

处于用户态的程序，通过触发中断，可以进入内核态，之后再通过中断返回，又可以恢复为用户态。系统调用就是这样，用户通过 `int 0x80` 中断指令触发了中断，CPU 切换至内核态，执行中断处理程序，之后中断程序返回，又从内核态切换回用户态。

但有个问题是，当前就是处于内核态，并不是由一个用户态程序通过中断而切换到的内核态，那怎么回到用户态呢？还是通过中断返回。Intel 设计的 CPU 就是可以没有中断也能中断返回，中断和中断返回的确是应该配套使用的，但也可以单独使用。

#figure(
```c
void main(void) {
    ...
    move_to_user_mode();
    ...
}

#define move_to_user_mode() \
_asm { \
    _asm mov eax,esp \
    _asm push 00000017h \
    _asm push eax \
    _asm pushfd \
    _asm push 0000000fh \
    _asm push offset l1 \
    _asm iretd /* 执行中断返回指令*/ \
_asm l1: mov eax,17h \
    _asm mov ds,ax \
    _asm mov es,ax \
    _asm mov fs,ax \
    _asm mov gs,ax \
}
```,
caption: [move_to_user_mode]
)

这个方法里直接就执行了中断返回指令 `iretd`。

中断返回理论上就是应该和中断配合使用的，而此时并不是真的发生了中断到这里，所以得假装发生了中断。中断发生时，CPU 会自动帮我们做如下的压栈操作。而中断返回时，CPU 又会帮我们把压栈的这些值返序赋值给响应的寄存器。这样就假装了中断的发生。

#figure(caption: [])[#image("images/chapter22-5.png", width: 55%)]

去掉错误码，刚好是五个参数，所以在代码中模仿 CPU 进行了五次压栈操作，*这样在执行 `iretd` 指令时，硬件会按顺序将刚刚压入栈中的数据，分别赋值给 `SS`、`ESP`、`EFLAGS`、`CS`、`EIP` 这几个寄存器*，这就感觉像是正确返回了一样，让其误以为这是通过中断进来的。

- 压入栈的 `CS` 和 `EIP` 就表示中断发生前代码所处的位置，这样中断返回后好继续去那里执行。
- 压入栈的 `SS` 和 `ESP` 表示中断发生前的栈的位置，这样中断返回后才好恢复原来的栈。
  #tip("Tip")[
  其中，特权级的转换，就体现在 `CS` 和 `SS` 寄存器的值里！
  ]

`CS` 和 `SS` 寄存器是段寄存器的一种，段寄存器里的值是段选择子
#figure(caption: [])[#image("images/chapter22-2.png", width: 60%)]

对着这个结构，我们看代码。

#figure(
```c
#define move_to_user_mode() \
_asm { \
    _asm mov eax,esp \
    _asm push 00000017h \ ; 给 SS 赋值
    _asm push eax \       ; 给 ESP 赋值
    _asm pushfd \         ; 给 EFLAGS 赋值
    _asm push 0000000fh \ ; 给 CS 赋值
    _asm push offset l1 \ ; 给 EIP 赋值
    _asm iretd /* 执行中断返回指令*/ \
_asm l1: mov eax,17h \
    _asm mov ds,ax \
    _asm mov es,ax \
    _asm mov fs,ax \
    _asm mov gs,ax \
}
```,
caption: [move_to_user_mode]
)

拿 `CS` 举例，给它赋值`0000000fh`(`0000000000001111b`)

最后两位 `11` 表示特权级为 `3`，即用户态。而刚刚说了，`CS` 寄存器里的特权级，表示 `CPL`，即当前处理器特权级。所以经过 `iretd` 返回之后，`CS` 的值就变成了它，而当前处理器特权级，也就变成了用户态特权级。

== 除了改变特权级之外

`CS = 0000000000001111b`,最后两位表示用户态。倒数第三位 `TI` 表示，前面的描述符索引，是从 `GDT` 还是 `LDT` 中取，`1` 表示 `LDT`。

`CS`的`TI`为 `1`，表示从局部描述符表中取到代码段描述符。`sched_init`中将0号`LDT`作为当前`LDT`的索引记录在了CPU的`lldt`寄存器中.

#figure(
```c
#define lldt(n) __asm__("lldt %%ax"::"a" (_LDT(n)))

void sched_init(void) {
    ...
    lldt(0);
    ...
}
```,
caption: [sched_init - lldt]
)

经过内核的初始化之后，整个GDT和LDT表的设计如图：
#figure(caption: [])[#image("images/chapter22-6.png", width: 60%)]

再看代码
#figure(
```c
void main(void) {
    ...
    move_to_user_mode();
    ...
}

#define move_to_user_mode() \
_asm { \
    _asm mov eax,esp \
    _asm push 00000017h \ ; 给 SS 赋值
    _asm push eax \       ; 给 ESP 赋值
    _asm pushfd \         ; 给 EFLAGS 赋值
    _asm push 0000000fh \ ; 给 CS 赋值
    _asm push offset l1 \ ; 给 EIP 赋值
    _asm iretd /* 执行中断返回指令*/ \
_asm l1: mov eax,17h \
    _asm mov ds,ax \
    _asm mov es,ax \
    _asm mov fs,ax \
    _asm mov gs,ax \
}
```,
caption: [move_to_user_mode]
)

把 `EIP` 寄存器赋值为`l1`的地址，所以 `iretd` 之后 CPU 就乖乖去那里执行了。所以其实从效果上看，就是顺序往下执行，只不过利用了 `iretd` 做了些特权级转换等工作。

同理，这里的栈段 `ss` 和数据段 `ds`，都被赋值为了 `17h`(`0000000000010111b`)。可以得知`CPL=11b,TI=1b,index=10b`，用户态，ldt

#pagebreak()
