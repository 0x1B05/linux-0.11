#import "../template.typ": *

= Intel 内存管理两板斧：分段与分页

#figure(
```asm
jmp after_page_tables
...
after_page_tables:
    push 0
    push 0
    push 0
    push L6
    push _main
    jmp setup_paging
L6:
    jmp L6
```,
caption: [head - 开启分页]
)

在没有开启分页机制时，由程序员给出的逻辑地址，需要先通过分段机制转换成物理地址。
但在开启分页机制后，逻辑地址仍然要先通过分段机制进行转换，只不过转换后不再是最终的物理地址，而是线性地址，然后再通过一次分页机制转换，得到最终的物理地址。
#figure(caption: [])[#image("images/chapter9-1.png", width:40%)]

linux0.11采用二级页表：
#figure(caption: [])[#image("images/chapter9-2.png", width: 70%)]

这一切都由计算机的一个硬件叫 MMU(内存管理单元)，有时也叫 PMMU，分页内存管理单元。由这个部件来负责将虚拟地址转换为物理地址。
 
整个过程我们不用操心，作为操作系统这个软件层，只需要提供好页目录表和页表即可，这种页表方案叫做二级页表，第一级叫页目录表 PDE，第二级叫页表 PTE。他们的结构如下。
#figure(caption: [])[#image("images/chapter9-3.png", width: 80%)]
再开启分页机制的开关。其实就是更改 cr0 寄存器中的一位即可（31 位）
#figure(caption: [])[#image("images/chapter9-4.png", width: 80%)]

然后，MMU 就可以进行分页的转换了。此后指令中的内存地址（程序员提供的逻辑地址），就统统要先经过分段机制的转换，再通过分页机制的转换，才能最终变成物理地址。

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

这段代码，就是把页表和页目录表在内存中写好，之后开启 `cr0` 寄存器的分页开关
当时 linux-0.11 认为，总共可以使用的内存不会超过 `16M`，也即最大地址空间为 `0xFFFFFF`。 而按照当前的页目录表和页表这种机制，1 个页目录表最多包含 1024 个页目录项（也就是 1024 个页表），1 个页表最多包含 1024 个页表项（也就是 1024 个页），1 页为 4KB（因为有 12 位偏移地址），因此，16M 的地址空间可以用 1 个页目录表 + 4 个页表搞定。
 
4（页表数）* 1024（页表项数） * 4KB（一页大小）= 16MB
 
所以，上面这段代码就是，将页目录表(`_pg_dir`)放在内存地址的最开头,之后紧挨着这个页目录表，放置 4 个页表，代码里也有这四个页表的标签项。

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

这些页目录表和页表放到了整个内存布局中最开头的位置，就是覆盖了开头的 system 代码了，不过被覆盖的 system 代码已经执行过了，所以无所谓。
同时，如 `idt` 和 `gdt` 一样，我们也需要通过一个寄存器告诉 CPU 我们把这些页表放在了哪里。(相当于告诉 `cr3` 寄存器，`0` 地址处就是页目录表，再通过页目录表可以找到所有的页表)
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

后面几行表示，填充 4 个页表的每一项，一共 4*1024=4096 项，依次映射到内存的前 16MB 空间。
#figure(caption: [])[#image("images/chapter9-2.png", width: 50%)]

#definition("Definition")[
线性地址：通过分段机制，将逻辑地址转换后的地址，叫做线性地址。而这个线性地址是有个范围的，这个范围就叫做线性地址空间，32 位模式下，线性地址空间就是 4G。
]

== 扩展资料

逻辑地址-线性地址-物理地址的转换: Intel 3A Chapter 3 Protected-Mode Memory Management
#figure(caption: [])[#image("images/chapter9-8.png", width: 80%)]
#figure(caption: [])[#image("images/chapter9-7.png", width: 80%)]
页目录表和页表的具体结构: Intel 3A Chapter 4.3 32-bit paging
#figure(caption: [])[#image("images/chapter9-9.png", width: 80%)]
#figure(caption: [])[#image("images/chapter9-10.png", width: 80%)]

#pagebreak()
