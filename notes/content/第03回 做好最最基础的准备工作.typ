#import "../template.typ": *

= 做好最最基础的准备工作

那我们接下来，就继续把我们的目光放在 go 这个标签的位置。

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

到这里操作系统的一些最最最最基础的准备工作，就做好了。操作系统在做的事情，就是给如何访问代码，如何访问数据，如何访问栈进行了一下内存的初步规划。
#figure(caption: [])[#image("images/chapter3-2.png", width: 70%)]

#pagebreak()
