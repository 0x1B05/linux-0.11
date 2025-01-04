#import "../template.typ": *

= 进入保护模式前的最后一次折腾内存 

进度`setup.s` 文件的第一行代码。
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
caption: [setup.s - start]
)

`int 0x10` 是触发 BIOS 提供的*显示服务中断处理程序*，而 `ah` 寄存器被赋值为 `0x03` 表示显示服务里具体的`读取光标位置功能`。这个 `int 0x10` 中断程序执行完毕并返回时，`dx` 寄存器里的值表示光标的位置，具体说来其高八位 `dh` 存储了行号，低八位 `dl` 存储了列号。
#figure(caption: [])[#image("images/chapter5-1.png", width:70%)]

#tip("Tip")[
计算机在加电自检后会自动初始化到文字模式，在这种模式下，一屏幕可以显示 25 行，每行 80 个字符，也就是 80 列。
]

下一步 `mov [0],dx` 就是把这个光标位置存储在 `[0]` 这个内存地址处。
#tip("Tip")[
前面我们说过，这个内存地址仅仅是偏移地址，还需要加上 `ds` 这个寄存器里存储的段基址，最终的内存地址是在 `0x90000` 处，这里存放着光标的位置，以便之后在初始化控制台的时候用到。
]

再接下来的几行代码，都是和刚刚一样的逻辑，调用一个 BIOS 中断获取点什么信息，然后存储在内存中某个位置，我们迅速浏览一下
#figure(
```asm
比如获取内存信息。
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
caption: [setup.s - 获取其他信息]
)

只需要知道最终存储在内存中的信息是什么，在什么位置，就好了，之后会用到他们的。

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

之后很快就会用 c 语言进行编程，虽然汇编和 c 语言也可以用变量的形式进行传递数据，但这需要编译器在链接时做一些额外的工作，所以这么多数据更方便的还是双方共同约定一个内存地址，我往这里存，你从这里取。

我们继续往下看。

```asm
cli         ; no interrupts allowed ;
```
就一行 `cli`，表示关闭中断的意思。因为后面我们要把原本是 BIOS 写好的中断向量表给覆盖掉，也就是给破坏掉了，写上我们自己的中断向量表，所以这个时候是不允许中断进来的。

继续看。

```asm
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
end_move:
    ...
```
看到后面那个 `rep movsw` 同前面的原理一样，也是做了个内存复制操作，最终的结果是，把内存地址 `0x10000` 处开始往后一直到 `0x90000` 的内容，统统复制到内存的最开始的 `0` 位置，大概就是这么个效果。
#figure(caption: [])[#image("images/chapter5-2.png", width:60%)]

我们重新梳理一下此时的内存布局。

#figure(caption: [])[#image("images/chapter5-3.png",width:30%)]
之前的什么 `0x7c00`，已经是过去式了，赶紧忘掉它，向前看！

#pagebreak()
