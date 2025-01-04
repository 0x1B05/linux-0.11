#import "../template.typ": *

= 按下键盘后为什么屏幕上就会有输出(`tty_init`)

`tty_init`执行完，我们将会具备键盘输入到显示器输出字符这个最常用的功能。
#figure(
```c
void tty_init(void)
{
    rs_init();
    con_init();
}
void rs_init(void)
{
    set_intr_gate(0x24,rs1_interrupt);
    set_intr_gate(0x23,rs2_interrupt);
    init(tty_table[1].read_q.data);
    init(tty_table[2].read_q.data);
    outb(inb_p(0x21)&0xE7,0x21);
}
void con_init(void) {
    ...
    if (ORIG_VIDEO_MODE == 7) {
        ...
        if ((ORIG_VIDEO_EGA_BX & 0xff) != 0x10) {...}
        else {...}
    } else {
        ...
        if ((ORIG_VIDEO_EGA_BX & 0xff) != 0x10) {...}
        else {...}
    }
    ...
}
```,
caption: [tty_init]
)

`rs_init`是串口中断的开启，以及设置对应的中断处理程序。
`con_init`有非常多的`if else`，这是为了应对不同的显示模式，来分配不同的变量值，那如果我们仅仅找出一个显示模式，这些分支就可以只看一个了。
 
显示模式：规定一个字符是如何显示在屏幕上的。如果可以随意操作内存和 CPU 等设备，如何操作才能使得你的显示器上，显示一个字符'a'呢？

#figure(caption: [])[#image("images/chapter16-1.png", width: 70%)]

内存中有这样一部分区域，是和显存映射的。就是往上图的这些内存区域中写数据，相当于写在了显存中。而往显存中写数据，就相当于在屏幕上输出文本了。

#example("Example")[
如果我们写这一行汇编语句。

```
mov [0xB8000],'h'
```

后面那个 'h' 相当于汇编编辑器帮我们转换成 ASCII 码的二进制数值，当然我们也可以直接写。

```
mov [0xB8000],0x68
```

其实就是往内存中 `0xB8000` 这个位置写了一个值，只要一写，屏幕上就会是这样。
#figure(caption: [])[#image("images/chapter16-2.png", width: 60%)]
]

具体说来，这片内存是每两个字节表示一个显示在屏幕上的字符，第一个是字符的编码，第二个是字符的颜色，那我们先不管颜色，如果多写几个字符就像这样。

```
mov [0xB8000],'h'
mov [0xB8002],'e'
mov [0xB8004],'l'
mov [0xB8006],'l'
mov [0xB8008],'o'
```

此时屏幕上就会是这样。
#figure(caption: [])[#image("images/chapter16-4.png", width: 60%)]

回过头看刚刚的代码，假设显示模式是现在的这种文本模式，条件分支就可以去掉好多。代码可以简化成这个样子。

#figure(
```c
#define ORIG_X          (*(unsigned char *)0x90000)
#define ORIG_Y          (*(unsigned char *)0x90001)
void con_init(void) {
    register unsigned char a;
    // 第一部分 获取显示模式相关信息
    video_num_columns = (((*(unsigned short *)0x90006) & 0xff00) >> 8);
    video_size_row = video_num_columns * 2;
    video_num_lines = 25;
    video_page = (*(unsigned short *)0x90004);
    video_erase_char = 0x0720;
    // 第二部分 显存映射的内存区域 
    video_mem_start = 0xb8000;
    video_port_reg  = 0x3d4;
    video_port_val  = 0x3d5;
    video_mem_end = 0xba000;
    // 第三部分 滚动屏幕操作时的信息
    origin  = video_mem_start;
    scr_end = video_mem_start + video_num_lines * video_size_row;
    top = 0;
    bottom  = video_num_lines;
    // 第四部分 定位光标并开启键盘中断
    gotoxy(ORIG_X, ORIG_Y);
    set_trap_gate(0x21,&keyboard_interrupt);
    outb_p(inb_p(0x21)&0xfd,0x21);
    a=inb_p(0x61);
    outb_p(a|0x80,0x61);
    outb(a,0x61);
}
```,
caption: [con_init]
)

#tip("Tip")[
    回忆之前setup.s存储的设备信息：
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

]

- 第一部分获取 `0x90006` 地址处的数据，就是获取显示模式等相关信息。
- 第二部分就是显存映射的内存地址范围，我们现在假设是 CGA 类型的文本模式，所以映射的内存是从 `0xB8000` 到 `0xBA000`。
- 第三部分是设置一些滚动屏幕时需要的参数，定义顶行和底行是哪里，这里顶行就是第一行，底行就是最后一行，很合理。
- 第四部分是把光标定位到之前保存的光标位置处（取内存地址 `0x90000` 处的数据），然后设置并开启键盘中断。开启键盘中断后，键盘上敲击一个按键后就会触发中断，中断程序就会读键盘码转换成 ASCII 码，然后写到光标处的内存地址，也就相当于往显存写，于是这个键盘敲击的字符就显示在了屏幕上。

目前可以实现

1. 根据已有信息已经可以实现往屏幕上的任意位置写字符，还能指定颜色。
2. 能接受键盘中断，根据键盘码中断处理程序就可以得知哪个键按下了。

一切的起点，就是第四步的 `gotoxy` 函数，定位当前光标。

#figure(
```c
#define ORIG_X          (*(unsigned char *)0x90000)
#define ORIG_Y          (*(unsigned char *)0x90001)
void con_init(void) {
    ...
    // 第四部分 定位光标并开启键盘中断
    gotoxy(ORIG_X, ORIG_Y);
    ...
}
```,
caption: [con_init - gotoxy]
)

这里面干嘛了呢？

#figure(
```c
static inline void gotoxy(unsigned int new_x, unsigned int new_y) {
   ...
   x = new_x; // 光标所在列
   y = new_y; // 光标所在行
   // pos 即根据x和y计算出来的内存指针
   // 往pos处写数据相当于往控制台的(x, y)处写入字符了
   pos = origin + y*video_size_row + (x<<1);
}
```,
caption: [gotoxy]
)

按下键盘后，触发键盘中断，之后的程序调用链是这样的。

#figure(
```c
_keyboard_interrupt:
    ...
    call _do_tty_interrupt
    ...
    
void do_tty_interrupt(int tty) {
   copy_to_cooked(tty_table+tty);
}

void copy_to_cooked(struct tty_struct * tty) {
    ...
    tty->write(tty);
    ...
}

// 控制台时 tty 的 write 为 con_write 函数
void con_write(struct tty_struct * tty) {
    ...
    __asm__("movb _attr,%%ah\n\t"
      "movw %%ax,%1\n\t"
      ::"a" (c),"m" (*(short *)pos)
      :"ax");
     pos += 2;
     x++;
    ...
}
```,
caption: [键盘终端调用链]
)

前面的过程不用管，看最后一个函数 `con_write` 中的关键代码。`__asm__` 内联汇编，就是把键盘输入的字符 `c` 写入 `pos` 指针指向的内存，相当于往屏幕输出了。之后两行 `pos+=2` 和 `x++`，就是调整所谓的光标。

写入一个字符，其实就是往内存的某处写个数据，然后顺便调整一下光标。由此我们也可以看出，光标的本质，其实就是这里的 `x`, `y`, `pos` 这仨变量而已。

我们还可以做换行效果，当发现光标位置处于某一行的结尾时（都知道屏幕上一共有几行几列了），就把光标计算出一个新值，让其处于下一行的开头。就一个小计算公式即可搞定，仍然在 `con_write` 源码处有体现，即判断列号 `x` 是否大于了总列数。

#figure(
```c
void con_write(struct tty_struct * tty) {
    ...
    if (x>=video_num_columns) {
        x -= video_num_columns;
        pos -= video_size_row;
        lf();
  }
  ...
}

static void lf(void) {
   if (y+1<bottom) {
      y++;
      pos += video_size_row;
      return;
   }
 ...
}
```,
caption: [控制台换行]
)

相似的，还可以实现滚屏的效果，无非就是当检测到光标已经出现在最后一行最后一列了，那就把每一行的字符，都复制到它上一行，其实就是算好哪些内存地址上的值，拷贝到哪些内存地址，就好了。这里大家自己看源码寻找。(源码位于`/kernel/chr_drv/console.c`)
 
有了这个初始化工作，就可以利用这些信息，弄几个小算法，实现各种我们常见控制台的操作。

所以 `console.c` 中的其他方法就是做这个事的，我们就不展开每一个功能的方法体了，简单看看有哪些方法。

#figure(
```c
// 定位光标的
static inline void gotoxy(unsigned int new_x, unsigned int new_y){}
// 滚屏，即内容向上滚动一行
static void scrup(void){}
// 光标同列位置下移一行
static void lf(int currcons){}
// 光标回到第一列
static void cr(void){}
...
// 删除一行
static void delete_line(void){}
```,
caption: [console.c]
)

`console.c` 是整个内核中代码量最大的文件，可是功能特别单一，也都很简单，主要是处理键盘各种不同的按键，需要写好多 switch case 等语句，完全没必要去展开。
 
到这里就正式讲完了 `tty_init` 的作用。此后，kernel就可以用它来方便地在控制台输出字符啦！想要在启动过程中告诉用户一些信息，以及后面内核完全建立起来之后，由用户用 shell 进行操作时手动输入命令，都是可以用到这里的代码的！

#pagebreak()
