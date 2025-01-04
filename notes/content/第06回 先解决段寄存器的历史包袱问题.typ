#import "../template.typ": *

= 先解决段寄存器的历史包袱问题 

接下来就要进行真正的第一项大工程了，那就是模式的转换，需要从现在的 16 位的实模式转变为之后 32 位的保护模式。这是 x86 的历史包袱问题，现在的 CPU 几乎都是支持 32 位模式甚至 64 位模式了，很少有还仅仅停留在 16 位的实模式下的 CPU。所以我们要为了这个历史包袱，写一段模式转换的代码，如果 Intel CPU 被重新设计而不用考虑兼容性，那么今天的代码将会减少很多甚至不复存在。

#figure(
```asm
lidt  idt_48      ; load idt with 0,0
lgdt  gdt_48      ; load gdt with whatever appropriate

idt_48:
    .word   0     ; idt limit=0
    .word   0,0   ; idt base=0L
```,
caption: [setup - 模式切换]
)

要理解这两条指令，就涉及到实模式和保护模式的第一个区别了。我们现在还处于实模式下, 当 CPU 切换到保护模式后，同样的代码，内存地址的计算方式并不一样:
- 实模式：段基址左移四位，再加上偏移地址
- 保护模式：`ds` 寄存器里存储的值，在实模式下叫做段基址，在保护模式下叫段选择子。段选择子里存储着段描述符的索引。
  #figure(caption: [])[#image("images/chapter6-1.png", width: 50%)] 
  通过段描述符索引，可以从全局描述符表 `gdt` 中找到一个段描述符，段描述符里存储着段基址。
  #figure(caption: [])[#image("images/chapter6-2.png",width:70%)]
  段基址取出来，再和偏移地址相加，就得到了物理地址，整个过程如下。
  #figure(caption: [])[#image("images/chapter6-3.png",width:70%)]

段寄存器（比如 `ds`、`ss`、`cs`）里存储的是段选择子，段选择子去全局描述符表中寻找段描述符，从中取出段基址。由操作系统把全局描述符表（`gdt`）在内存中这个位置信息存储在一个叫 `gdtr` 的寄存器中。

```asm
lgdt    gdt_48
```

其中 `lgdt` 就表示把后面的值（`gdt_48`）放在 `gdtr` 寄存器中，`gdt_48` 标签

```asm
gdt_48:
    .word   0x800       ; gdt limit=2048, 256 GDT entries
    .word   512+gdt,0x9 ; gdt base = 0X9xxxx
```
可以看到这个标签位置处表示一个 48 位的数据，其中高 32 位存储着的正是全局描述符表 `gdt` 的内存地址`0x90200 + gdt`, `gdt` 是个标签，表示在本文件内的偏移量，而本文件是 `setup.s`，编译后是放在 `0x90200` 这个内存地址的
#figure(caption: [])[#image("images/chapter6-4.png", width:60%)]
#figure(caption: [])[#image("images/chapter6-5.png",width:40%)]

那 `gdt` 这个标签处，就是全局描述符表在内存中的真正数据了。

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
- 第二个是代码段描述符（type=code）
- 第三个是数据段描述符（type=data）

第二个和第三个段描述符的段基址都是 0，也就是之后在逻辑地址转换物理地址的时候，通过段选择子查找到无论是代码段还是数据段，取出的段基址都是 0，那么物理地址将直接等于程序员给出的逻辑地址（准确说是逻辑地址中的偏移地址）。

#figure(caption: [])[#image("images/chapter6-6.png", width: 30%)]

接下来我们看看目前的内存布局。

#figure(caption: [])[#image("images/chapter6-7.png", width: 50%)]

`idtr` 寄存器也画出来了，这个是中断描述符表。中断描述符表是用来在发生中断时，CPU 拿着中断号去中断描述符表中寻找中断处理程序的地址，找到后就跳到相应的中断程序中去执行。

== 扩展资料

保护模式下逻辑地址到线性地址（不开启分页时就是物理地址）的转化(Intel 手册： Volume 3 Chapter 3.4 Logical And Linear Addresses)：
#figure(caption: [])[#image("images/chapter6-8.png", width:80%)]

段描述符结构和详细说明(Intel 手册： Volume 3 Chapter 3.4.5 Segment Descriptors)：
#figure(caption: [])[#image("images/chapter6-9.png", width:80%)]

#pagebreak()
