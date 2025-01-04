#import "../template.typ": *

= 自己给自己挪个地儿

接下来我们带着这两行代码，继续往下看几行。

#figure(
```asm
mov ax,0x07c0
mov ds,ax
mov ax,0x9000
mov es,ax # es <- ax <- 0x9000
mov cx,#256 # cx <- 256
sub si,si # si = si - si = 0, si寄存器清零
sub di,di # di = di - di = 0, di寄存器清零
rep movw
```,
caption: [接下来几行]
)

经过以上几行代码，寄存器的值如图所示
#figure(caption: [])[#image("images/chapter2-1.png", width: 60%)]

给这些寄存器附上值其实就是为下一条指令服务的:

```asm
rep movw
```

其中 `rep` 表示重复执行后面的指令, 而后面的指令 `movw` 表示复制一个字（word 16位），那其实就是不断重复地复制一个字。

那下面自然就有三连问：
- 重复执行多少次？是 `cx` 寄存器中的值，也就是 256 次。
- 从哪复制到哪？是从 `ds:si` 处复制到 `es:di` 处。
- 一次复制多少？刚刚说过了，复制一个字，16 位，也就是两个字节。

*即：将内存地址 `0x7c00` 处开始往后的 512 Byte，原封不动复制到 `0x90000` 处。*
#figure(caption: [])[#image("images/chapter2-2.png", width: 60%)]

再往后是一个跳转指令。

#figure(
```asm
jmpi go,0x9000
go: 
  mov ax,cs
  mov ds,ax
```,
caption: [跳转指令]
)

#tip("Tip")[
`jmpi` 是一个段间跳转指令，表示跳转到 `0x9000:go` 处执行。

段基址 : 偏移地址 段基址仍然要先左移四位，因此结论就是跳转到 `0x90000 + go` 这个内存地址处执行。
]

#figure(caption: [])[#image("images/chapter2-3.png", width:60%)]

go 就是一个*标签*，最终编译成机器码的时候会被翻译成一个值，这个值就是 go 这个标签在文件内的偏移地址。假如 `mov ax,cx` 这行代码位于最终编译好后的二进制文件的 `0x08` 处，那 `go` 就等于 `0x08`，而最终 CPU 跳转到的地址就是 `0x90008` 处。

#pagebreak()
