#import "../template.typ": *

= 你的键盘是什么时候生效的(`trap_init`)

计算机刚刚启动时，按下键盘是不生效的，但是过了一段时间后，再按下键盘就有效果了。到底过了多久之后，按下键盘才有效果呢？

按下键盘后会触发中断，CPU 收到键盘中断后，根据中断号，寻找由操作系统写好的键盘中断处理程序。这个中断处理程序会把你的键盘码放入一个队列中，由相应的用户程序或内核程序读取，并显示在控制台，或者其他用途，这就代表你的键盘生效了。

#figure(
```c
void main(void) {
    ...
    trap_init();
    ...
}
```,
caption: [main - trap_init]
)

#figure(
```c
void trap_init(void) {
    int i;
    set_trap_gate(0,&divide_error);
    set_trap_gate(1,&debug);
    set_trap_gate(2,&nmi);
    set_system_gate(3,&int3);   /* int3-5 can be called from all */
    set_system_gate(4,&overflow);
    set_system_gate(5,&bounds);
    set_trap_gate(6,&invalid_op);
    set_trap_gate(7,&device_not_available);
    set_trap_gate(8,&double_fault);
    set_trap_gate(9,&coprocessor_segment_overrun);
    set_trap_gate(10,&invalid_TSS);
    set_trap_gate(11,&segment_not_present);
    set_trap_gate(12,&stack_segment);
    set_trap_gate(13,&general_protection);
    set_trap_gate(14,&page_fault);
    set_trap_gate(15,&reserved);
    set_trap_gate(16,&coprocessor_error);
    for (i=17;i<48;i++)
        set_trap_gate(i,&reserved);
    set_trap_gate(45,&irq13);
    set_trap_gate(39,&parallel_interrupt);
}
```,
caption: [trap_init]
)

#figure(
```c
void trap_init(void) {
    int i;
    // set 了一堆 trap_gate
    set_trap_gate(0, &divide_error);
    ... 
    // 又 set 了一堆 system_gate
    set_system_gate(45, &bounds);
    ...
    // 又又批量 set 了一堆 trap_gate
    for (i=17;i<48;i++)
        set_trap_gate(i, &reserved);
    ...
}
```,
caption: [trap_init 简化版]
)

首先我们看 `set_trap_gate` 和 `set_system_gate`, 最终的效果就是在中断描述符表中插入了一个中断描述符。这段代码就是往这个 `idt` 表里一项一项地写东西，其对应的中断号就是第一个参数，中断处理程序就是第二个参数。
#figure(
```c
#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \
    "movw %0,%%dx\n\t" \
    "movl %%eax,%1\n\t" \
    "movl %%edx,%2" \
    : \
    : "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \
    "o" (*((char *) (gate_addr))), \
    "o" (*(4+(char *) (gate_addr))), \
    "d" ((char *) (addr)),"a" (0x00080000))

#define set_trap_gate(n,addr) \
    _set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
    _set_gate(&idt[n],15,3,addr)
```,
caption: [`_set_gate`]
)

产生的效果就是，之后如果来一个中断后，CPU 根据其中断号，就可以到这个中断描述符表 `idt` 中找到对应的中断处理程序了。
 
#example("Example")[
```
set_trap_gate(0,&divide_error);
```
就是设置 0 号中断，对应的中断处理程序是 `divide_error`。等 CPU 执行了一条除零指令的时候，会从硬件层面发起一个 0 号异常中断，然后执行由我们操作系统定义的 `divide_error` 也就是除法异常处理程序，执行完之后再返回。
]
 
#example("Example")[
```
set_system_gate(5,&overflow);
```
就是设置 5 号中断，对应的中断处理程序是 `overflow`，是边界出错中断。
]
 

#tip("Tip")[
这个 `trap` 与 `system` 的区别仅仅在于，设置的中断描述符的特权级不同，前者是 0（内核态），后者是 3（用户态）就理解为都是设置一个中断号和中断处理程序的对应关系就好了。
]

再往后看，批量操作这里。17 到 48 号中断都批量设置为了 `reserved` 函数，这是暂时的，后面各个硬件初始化时要重新设置好这些中断，把暂时的这个给覆盖掉。

#figure(
```c
void trap_init(void) {
    ...
    for (i=17;i<48;i++)
        set_trap_gate(i,&reserved);
    ...
}
```,
caption: [trap_init - 批量操作]
)

所以整段代码执行下来，内存中那个 `idt` 的位置会变成如下的样子。
#figure(caption: [])[#image("images/chapter14-1.png", width: 70%)]

这行代码过去后，键盘依然不好使，键盘产生的中断的中断号是 `0x21`，此时这个中断号还仅仅对应着一个临时的中断处理程序 `&reserved`，我们接着往后看。

#figure(
```c
void main(void) {
    ...
    trap_init();
    ...
    tty_init();
    ...
}

void tty_init(void) {
    rs_init();
    con_init();
}

void con_init(void) {
    ...
    set_trap_gate(0x21,&keyboard_interrupt);
    ...
}
```,
caption: [tty_init]
)

注意到 `trap_init` 后有个 `tty_init`，最后根据调用链，会调用到一行添加 `0x21` 号中断处理程序的代码，就是刚刚熟悉的 `set_trap_gate`。而后面的 `keyboard_interrupt` 就是键盘的中断处理程序！就是从这一行代码开始，我们的键盘生效了！不过还有点小问题，现在的中断处于禁用状态，不论是键盘中断还是其他中断，通通都不好使。

而 `main` 方法继续往下读，还有一行`sti`，最终会对应一个同名的汇编指令 `sti`，表示允许中断。所以这行代码之后，键盘才真正开始生效！

#figure(
```c
void main(void) {
    ...
    trap_init();
    ...
    tty_init();
    ...
    sti();
    ...
}
```,
caption: [main - 允许中断]
)

#pagebreak()
