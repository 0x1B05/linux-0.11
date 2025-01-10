#import "../template.typ":*

= shell命令全流程

== 键盘输入命令

新建一个`info.txt` 文件。

```txt
name:flash
age:28
language:java
```

在命令行输入`cat`命令。

```sh
[root@linux0.11] cat info.txt | wc -l
3
```

最初，电脑屏幕上只有

```sh
[root@linux0.11]
```

按下按键 `'c'`，将会变成这样。

```sh
[root@linux0.11] c
```

接下来，再依次按下 `'a'`、`'t'`、空格、`'i'` 等等。

```sh
[root@linux0.11] cat info.txt | wc -l
```

就从按下键盘上的 `'c'` 键开始说起。凭什么按下键盘后，屏幕上就会出现如此的变化?

首先，得益于 `tty_init` 中讲述的一行代码。

#figure(
```c
// console.c
void con_init(void) {
    ...
    set_trap_gate(0x21,&keyboard_interrupt);
    ...
}
```,
caption: [con_init]
)

成功将键盘中断绑定在了 `keyboard_interrupt` 这个中断处理函数上，也就是说当按下键盘 'c' 时，CPU 的中断机制将会被触发，最终执行到这个 `keyboard_interrupt` 函数中。

#figure(
```c
// keyboard.s
keyboard_interrupt:
    ...
    // 读取键盘扫描码
    inb $0x60,%al
    ...
    // 调用对应按键的处理函数
    call *key_table(,%eax,4)
    ...
    // 0 作为参数，调用 do_tty_interrupt
    pushl $0
    call do_tty_interrupt
    ...
```,
caption: [keyboard_interrupt]
)

- `inb $0x60,%al`: 首先通过 IO 端口操作，从键盘中读取了刚刚产生的键盘扫描码，就是按下 `'c'` 时产生的键盘扫描码。
- `call *key_table(,%eax,4)`随后，在 `key_table` 中寻找不同按键对应的不同处理函数，比如普通的一个字母对应的字符 `'c'` 的处理函数为 `do_self`，`do_self`会将扫描码转换为 ASCII 码，并放入一个队列。
- 接下来调用 `do_tty_interrupt` 函数，就是处理终端的中断处理函数，这里传递了一个参数 `0`(`pushl $0`)。

=== `call *key_table(,%eax,4)`

#figure(
```c
// keyboard.s
keyboard_interrupt:
    ...
    // 读取键盘扫描码
    inb $0x60,%al
    ...
    // 调用对应按键的处理函数
    call *key_table(,%eax,4)
    ...
    // 0 作为参数，调用 do_tty_interrupt
    pushl $0
    call do_tty_interrupt
    ...
key_table:
    .long none,do_self,do_self,do_self  /* 00-03 s0 esc 1 2 */
    .long do_self,do_self,do_self,do_self   /* 04-07 3 4 5 6 */
    ...
    .long do_self,do_self,do_self,do_self   /* 20-23 d f g h */
    ...
```,
caption: [key_table]
)

可以看出，普通的字符 `abcd` 这种，对应的处理函数是 `do_self`。

#figure(
```c
// keyboard.s
do_self:
    ...
    // 扫描码转换为 ASCII 码
    lea key_map,%ebx
    1: movb (%ebx,%eax),%al
    ...
    // 放入队列
    call put_queue
```,
caption: [do_self]
)

最后调用了 `put_queue` 函数。

#figure(
```c
// tty_io.c
struct tty_queue * table_list[]={
    &tty_table[0].read_q, &tty_table[0].write_q,
    &tty_table[1].read_q, &tty_table[1].write_q,
    &tty_table[2].read_q, &tty_table[2].write_q
};

// keyboard.s
put_queue:
    ...
    movl table_list,%edx # read-queue for console
    movl head(%edx),%ecx
    ...
```,
caption: [put_queue]
)

`tty_table` 是终端设备表，在 Linux 0.11 中定义了三项，分别是控制台、串行终端 1 和串行终端 2。往屏幕上输出内容的终端，是 0 号索引位置处的控制台终端。

#figure(
```c
// tty.h
// tty_struct用来描述一个终端的属性
struct tty_struct {
    struct termios termios;
    int pgrp;
    int stopped;
    void (*write)(struct tty_struct * tty);
    struct tty_queue read_q;
    struct tty_queue write_q;
    struct tty_queue secondary;
};
struct tty_queue {
    unsigned long data;
    unsigned long head;
    unsigned long tail;
    struct task_struct * proc_list;
    char buf[TTY_BUF_SIZE];
};
struct tty_struct tty_table[] = {
    {
        {...},
        0,          /* initial pgrp */
        0,          /* initial stopped */
        con_write,
        {0,0,0,0,""},       /* console read-queue */
        {0,0,0,0,""},       /* console write-queue */
        {0,0,0,0,""}        /* console secondary queue */
    },
    {...},
    {...}
};
```,
caption: [tty_table]
)

- `termios` 是定义了终端的各种模式，包括读模式、写模式、控制模式等。
- `void (*write)(struct tty_struct * tty)` 是一个接口函数，在`tty_table`中也可以看出被定义为了 `con_write`，也就是说今后调用这个`0`号终端的写操作时，将会调用的是这个 `con_write` 函数。
- 三个队列分别为读队列 `read_q`，写队列 `write_q` 以及一个辅助队列 `secondary`。

可以看出，`put_queue` 正是操作了 `tty_table[0]`，也就是控制台终端 `tty` 的 `read_q` 队列，进行入队操作。


== `call do_tty_interrupt`

#figure(
```c
// tty_io.c
void do_tty_interrupt(int tty) {
    copy_to_cooked(tty_table+tty);
}

void copy_to_cooked(struct tty_struct * tty) {
    ...
}
```,
caption: [do_tty_interrupt]
)

`do_tty_interrupt` 就是将 `keyboard_interrupt` 时传入的参数 `0`，作为 `tty_table` 的索引，找到 `tty_table` 中的第 `0` 项作为下一个函数的入参。

#figure(
```c
// tty_io.c
void do_tty_interrupt(int tty) {
    copy_to_cooked(tty_table+tty);
}

void copy_to_cooked(struct tty_struct * tty) {
    signed char c;
    while (!EMPTY(tty->read_q) && !FULL(tty->secondary)) {
        // 从 read_q 中取出字符
        GETCH(tty->read_q,c);
        ...
        // 这里省略了一大坨行规则处理代码
        ...
        // 将处理过后的字符放入 secondary
        PUTCH(c,tty->secondary);
    }
    wake_up(&tty->secondary.proc_list);
}
```,
caption: [copy_to_cooked]
)

展开 `copy_to_cooked` 。在 `copy_to_cooked` 函数里就是个循环，只要`read_q` 不为空，且辅助队列 `secondary` 不满，就不断从 `read_q` 中取出字符，经过处理，写入 `secondary` 队列里。

#figure(caption: [])[#image("images/chapter36-1.png", width: 60%)]



否则(`read_q`为空或`secondary`满)，就唤醒等待这个辅助队列 `secondary` 的进程，之后就由进程自己决定做法。中间很多 `if` 判断都是一个目的，举其中一个简单的例子。

#figure(
```c
#define NCCS 17
struct termios {
    unsigned long c_iflag;		/* input mode flags */
    unsigned long c_oflag;		/* output mode flags */
    unsigned long c_cflag;		/* control mode flags */
    unsigned long c_lflag;		/* local mode flags */
    unsigned char c_line;		/* line discipline */
    unsigned char c_cc[NCCS];	/* control characters */
};

#define IUCLC   0001000
#define _I_FLAG(tty,f)  ((tty)->termios.c_iflag & f)
#define I_UCLC(tty) _I_FLAG((tty),IUCLC)

void copy_to_cooked(struct tty_struct * tty) {
    ...
    // 这里省略了一大坨行规则处理代码
    if (I_UCLC(tty))
        c=tolower(c);
    ...
}
```,
caption: [copy_to_cooked - if]
)

就是通过判断 `tty` 中的 `termios`，来决定对读出的字符 `c` 做一些处理。在这里，就是判断 `termios` 中的 `c_iflag` 中的第 `4` 位是否为 `1`，来决定是否要将读出的字符 `c` 由大写变为小写。`termios` 就是定义了终端的模式。

比如是否要将大写变为小写，是否将回车字符替换成换行字符，是否接受键盘控制字符信号如 `ctrl + c` 等。这些模式实现了 POSIX.1 中所规定的 #link("https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap11.html#tag_11")[termios标准]

目前可以总结出，按下键盘后。
#figure(caption: [])[#image("images/chapter36-3.png", width: 60%)]

=== 放入 `secondary` 队列之后

这就涉及到上层进程调用终端的读函数，将这个字符取走了。上层经过库函数、文件系统函数等，最终会调用到 `tty_read` 函数，将字符从 `secondary` 队列里取走。

#figure(
```c
#define GETCH(queue,c) \
(void)({c=(queue).buf[(queue).tail];INC((queue).tail);})

// tty_io.c
int tty_read(unsigned channel, char * buf, int nr) {
    ...
    GETCH(tty->secondary, c);
    ...
}
```,
caption: [tty_read]
)

取走后就是取决于上层应用程序的事了。假如要写到控制台终端，那上层应用程序会经过库函数、文件系统函数等层层调用，最终调用到 `tty_write` 函数。

#figure(
```c
// tty_io.
int tty_write(unsigned channel, char * buf, int nr) {
    ...
    PUTCH(c,tty->write_q);
    ...
    tty->write(tty);
    ...
}
```,
caption: [tty_write]
)

这个函数首先会将字符 `c` 放入 `write_q` 这个队列，然后调用 `tty` 里设定的 `write` 函数。终端控制台这个 `tty`  初始化的 `write` 函数是 `con_write`，即是 `console` 的写函数。

#figure(
```c
// console.c
void con_write(struct tty_struct * tty) {
      ...
}
```,
caption: [con_write]
)

这个函数在 `tty_init` 时提到了，最终会配合显卡，在屏幕上输出字符。

#figure(caption: [])[#image("images/chapter36-4.png", width: 60%)]

核心点就是三个队列 `read_q`，`secondary` 以及 `write_q`。

其中 `read_q` 是键盘按下按键后，进入到键盘中断处理程序 `keyboard_interrupt` 里，最终通过 `put_queue` 函数字符放入 `read_q` 这个队列。

`secondary` 是 `read_q` 队列里的未处理字符，通过 `copy_to_cooked` 函数，经过一定的 `termios` 规范处理后，将处理过后的字符放入 `secondary`。

然后，进程通过 `tty_read` 从 `secondary` 里读字符，通过 `tty_write` 将字符写入 `write_q`，最终 `write_q` 中的字符可以通过 `con_write` 这个控制台写函数，将字符打印在显示器上。

现在已经成功做到把这样一个字符串输入并回显在显示器上了。

```sh
[root@linux0.11] cat info.txt | wc -l
```

== shell程序读取命令

```sh
[root@linux0.11] cat info.txt | wc -l
```
shell 程序如何读取到输入的这条命令的?

两件事情。

1. 键盘输入的字符，此时已经到达了控制台终端 `tty` 结构中的 `secondary` 这个队列里。
2. shell 程序将通过上层的 `read` 函数调用，来读取这些字符。

#figure(
```c
// xv6-public sh.c
int main(void) {
    static char buf[100];
    // 读取命令
    while(getcmd(buf, sizeof(buf)) >= 0){
        // 创建新进程
        if(fork() == 0)
            // 执行命令
            runcmd(parsecmd(buf));
        // 等待进程退出
        wait();
    }
}

int getcmd(char *buf, int nbuf) {
    ...
    gets(buf, nbuf);
    ...
}

char* gets(char *buf, int max) {
    int i, cc;
    char c;
  
    for(i=0; i+1 < max; ){
      cc = read(0, &c, 1);
      if(cc < 1)
        break;
      buf[i++] = c;
      if(c == '\n' || c == '\r')
        break;
    }
    buf[i] = '\0';
    return buf;
}
```,
caption: [shell]
)

shell 程序会通过 `getcmd` 函数最终调用到 `read` 函数一个字符一个字符读入到`buf`里，直到读到了换行符（`\n`或`\r`）的时候这些字符将作为一个完整的命令，返回传入给 `runcmd` 函数执行。

`read` 函数是个用户态的库函数，最终会通过系统调用中断，执行 `sys_read` 函数把之前键盘输入并转移到 `secondary` 这个队列里的字符给读出来。



#figure(
```c
// read_write.c
// fd = 0, count = 1
int sys_read(unsigned int fd,char * buf,int count) {
    struct file * file = current->filp[fd];
    // 校验 buf 区域的内存限制
    verify_area(buf,count);
    struct m_inode * inode = file->f_inode;
    // 管道文件
    if (inode->i_pipe)
        return (file->f_mode&1)?read_pipe(inode,buf,count):-EIO;
    // 字符设备文件
    if (S_ISCHR(inode->i_mode))
        return rw_char(READ,inode->i_zone[0],buf,count,&file->f_pos);
    // 块设备文件
    if (S_ISBLK(inode->i_mode))
        return block_read(inode->i_zone[0],&file->f_pos,buf,count);
    // 目录文件或普通文件
    if (S_ISDIR(inode->i_mode) || S_ISREG(inode->i_mode)) {
        if (count+file->f_pos > inode->i_size)
            count = inode->i_size - file->f_pos;
        if (count<=0)
            return 0;
        return file_read(inode,file,buf,count);
    }
    // 不是以上几种，就报错
    printk("(Read)inode->i_mode=%06o\n\r",inode->i_mode);
    return -EINVAL;
}
```,
caption: [sys_read]
)

这个最上层的 `sys_read`，把读取管道文件、字符设备文件、块设备文件、目录文件或普通文件，都放在了同一个方法里处理，这个方法是所有读操作的统一入口。

`read` 的第一个参数是 `0`，也就是 `0` 号文件描述符，shell 进程是由进程 1 通过 `fork` 创建出来的，而进程 1 在 `init` 的时候打开了 `/dev/tty0` 作为 `0` 号文件描述符。

#figure(
```c
// main.c
void init(void) {
    setup((void *) &drive_info);
    (void) open("/dev/tty0",O_RDWR,0);
    (void) dup(0);
    (void) dup(0);
}
```,
caption: [init]
)

而 `/dev/tty0` 的文件类型，即其 inode 中的 `i_mode` 字段，表示为字符型设备，所以最终会走到 `rw_char` ，文件系统的第一层划分就走完了。

#figure(
```c
// char_dev.c
static crw_ptr crw_table[]={
    NULL,       /* nodev */
    rw_memory,  /* /dev/mem etc */
    NULL,       /* /dev/fd */
    NULL,       /* /dev/hd */
    rw_ttyx,    /* /dev/ttyx */
    rw_tty,     /* /dev/tty */
    NULL,       /* /dev/lp */
    NULL};      /* unnamed pipes */

int rw_char(int rw,int dev, char * buf, int count, off_t * pos) {
    crw_ptr call_addr;

    if (MAJOR(dev)>=NRDEVS)
        return -ENODEV;
    if (!(call_addr=crw_table[MAJOR(dev)]))
        return -ENODEV;
    return call_addr(rw,MINOR(dev),buf,count,pos);
}
```,
caption: [rw_char]
)

根据 `dev` 这个参数，计算出主设备号为 `4`，次设备号为 `0`，所以会走到 `rw_ttyx` 方法。

#figure(
```c
// char_dev.c
static int rw_ttyx(int rw,unsigned minor,char * buf,int count,off_t * pos) {
    return ((rw==READ)?tty_read(minor,buf,count):
        tty_write(minor,buf,count));
}
```,
caption: [rw_ttyx]
)

根据 `rw == READ` 走到读操作分支 `tty_read`。(省略了关于信号和超时时间等非核心的代码)

#figure(
```c
// tty_io.c
// channel=0, nr=1
int tty_read(unsigned channel, char * buf, int nr) {
    struct tty_struct * tty = &tty_table[channel];
    char c, * b=buf;
    while (nr>0) {
        ...
        if (EMPTY(tty->secondary) ...) {
            sleep_if_empty(&tty->secondary);
            continue;
        }
        do {
            GETCH(tty->secondary,c);
            ...
            put_fs_byte(c,b++);
            if (!--nr) break;
        } while (nr>0 && !EMPTY(tty->secondary));
        ...
    }
    ...
    return (b-buf);
}
```,
caption: [tty_read]
)

入参有三个参数:
- `channel=0`，表示 `tty_table` 里的控制台终端这个具体的设备。
- `buf` 是要读取的数据拷贝到内存的位置指针，也就是用户缓冲区指针。
- `nr` 为 `1`，表示要读出 `1` 个字符。

整个方法，其实就是不断从 `secondary` 队列里取出字符，然后放入 `buf` 指所指向的内存。
 
如果要读取的字符数 `nr` 被减为 `0`，说明已经完成了读取任务，或者说 `secondary` 队列为空，说明不论任务完没完成都没有字符继续读了，那此时调用 `sleep_if_empty` 将进程阻塞，等待被唤醒。

#figure(
```c
sleep_if_empty(&tty->secondary);

// tty_io.c
static void sleep_if_empty(struct tty_queue * queue) {
    cli();
    while (!current->signal && EMPTY(*queue))
        interruptible_sleep_on(&queue->proc_list);
    sti();
}

// sched.c
void interruptible_sleep_on(struct task_struct **p) {
    struct task_struct *tmp;
    ...
    tmp=*p;
    *p=current;
repeat: current->state = TASK_INTERRUPTIBLE;
    schedule();
    if (*p && *p != current) {
        (**p).state=0;
        goto repeat;
    }
    *p=tmp;
    if (tmp)
        tmp->state=0;
}
```,
caption: [sleep_if_empty]
)

先关注一句关键的代码，就是`current->state = TASK_INTERRUPTIBLE;`将当前进程的状态设置为可中断等待。

那么执行到进程调度程序时，当前进程将不会被调度，也就相当于阻塞了。进程被阻塞了，什么时候被唤醒呢？
- 再次按下键盘，使得 `secondary` 队列中有字符，就打破了为空的条件，此时就应该将之前的进程唤醒了。

#figure(
```c
// tty_io.c
void do_tty_interrupt(int tty) {
    copy_to_cooked(tty_table+tty);
}

void copy_to_cooked(struct tty_struct * tty) {
    ...
    wake_up(&tty->secondary.proc_list);
}
```,
caption: [copy_to_cooked]
)

可以看到，在 `copy_to_cooked` 里，在将 `read_q` 队列中的字符处理后放入 `secondary` 队列中的最后一步，就是唤醒 `wake_up` 这个队列里的等待进程。而 `wake_up` 函数就是修改一下状态，使其变成可运行的状态。

#figure(
```c
// sched.c
void wake_up(struct task_struct **p) {
    if (p && *p) {
        (**p).state=0;
    }
}
```,
caption: [wake_up]
)

总体流程。

#figure(caption: [])[#image("images/chapter37-1.png", width: 60%)]

== 进程的阻塞与唤醒

`sleep_on` 和 `wake_up` 是进程的阻塞与唤醒机制的实现

表示进程的数据结构是 `task_struct`，其中有一个 `state` 字段表示进程的状态，它在 Linux 0.11 里有五种枚举值。

#figure(
```c
// shed.h
#define TASK_RUNNING          0 // 运行态
#define TASK_INTERRUPTIBLE    1 // 可中断等待状态。
#define TASK_UNINTERRUPTIBLE  2 // 不可中断等待状态
#define TASK_ZOMBIE           3 // 僵死状态
#define TASK_STOPPED          4 // 停止
```,
caption: [task_struct->state]
)

当进程首次被创建时，也就是 `fork` 函数执行后，它的初始状态是 0，也就是运行态。

#figure(
```c
// system_call.s
_sys_fork:
    ...
    call _copy_process
    ...

// fork.c
int copy_process(...) {
    ...
    p->state = TASK_RUNNING;
    ...
}
```,
caption: [进程创建初始状态]
)

只有当处于运行态的进程，才会被调度机制选中，送入 CPU 开始执行。

#figure(
```c
// sched.c
void schedule (void) {
    ...
    if ((*p)->state == TASK_RUNNING && (*p)->counter > c) {
        ...
        next = i;
    }
    ...
    switch_to (next);
}
```,
caption: [schedule]
)

使一个进程阻塞只需要将其 `state` 字段，变成非 `TASK_RUNNING` 也就是非运行态，即可让它暂时不被 CPU 调度，也就达到了阻塞的效果。唤醒也就是再将对应进程的 `state` 字段变成 `TASK_RUNNING` 即可。

Linux 0.11 中的阻塞与唤醒，就是 `sleep_on` 和 `wake_up` 函数。其中 `sleep_on` 函数将 `state` 变为 `TASK_UNINTERRUPTIBLE`。而 `wake_up` 函数将 `state` 变回为 `TASK_RUNNING`，也就是 `0`。

#figure(
```c
// sched.c
void sleep_on (struct task_struct **p) {
    struct task_struct *tmp;
    ...
    tmp = *p;
    *p = current;
    current->state = TASK_UNINTERRUPTIBLE;
    schedule();
    if (tmp)
        tmp->state = 0;
}
void wake_up (struct task_struct **p) {
    (**p).state = 0;
}
```,
caption: [sleep_on && wake_up]
)

`sleep_on` 函数除了改变 `state` 状态之外，还有些其他的操作

当首次调用 `sleep_on` 函数时，比如 `tty_read` 在 `secondary` 队列为空时调用 `sleep_on`，传入的 `*p` 为 `NULL`，因为此时还没有等待 `secondary` 这个队列的任务。

#figure(
```c
struct tty_queue {
    ...
    struct task_struct * proc_list;
};

struct tty_struct {
    ...
    struct tty_queue secondary;
};

int tty_read(unsigned channel, char * buf, int nr) {
    ...
    sleep_if_empty(&tty->secondary);
    ...
}

static void sleep_if_empty(struct tty_queue * queue) {
    ...
    interruptible_sleep_on(&queue->proc_list);
    ...
}
```,
caption: [sleep_if_empty]
)

通过 `tmp = *p` 和 `*p = current` 两个赋值操作，此时： `tmp = NULL, *p = 当前任务`, 同时也使得 `proc_list` 指向了当前任务的 `task_struct`。

#figure(caption: [])[#image("images/chapter38-1.png", width: 60%)]

当有另一个进程调用了 `tty_read` 读取了同一个 `tty` 的数据时，就需要再次 `sleep_on`，此时 `*p=先前任务`。那么经过 `tmp = *p` 和 `*p = current` 两个赋值操作后，会变成这个样子。
#figure(caption: [])[#image("images/chapter38-2.png", width: 60%)]

也就是说，通过每一个当前任务所在的代码块中的 `tmp` 变量，总能找到上一个正在同样等待一个资源的进程，因此也就形成了一个链表。

当某进程调用了 `wake_up` 函数唤醒 `proc_list` 上指向的第一个任务时，该任务便会在 `sleep_on` 函数执行完 `schedule()` 后被唤醒并执行下面的代码，把 `tmp` 指针指向的上一个任务也同样唤醒。

#figure(
```c
// sched.c
void sleep_on (struct task_struct **p) {
    struct task_struct *tmp;
    ...
    tmp = *p;
    *p = current;
    current->state = TASK_UNINTERRUPTIBLE;
    schedule();
    if (tmp)
        tmp->state = 0;
}
```,
caption: [sleep_on - 唤醒]
)

唤醒其实就是把 `state` 变成 `0`(`TASK_RUNNING`运行态)。

而上一个进程唤醒后，和这个被唤醒的进程一样，也会走过它自己的 `sleep_on` 函数的后半段，把它的上一个进程，也就是上上一个进程唤醒。通过一个 `wake_up` 函数，以及上述这种 `tmp` 变量的巧妙设计，就能制造出唤醒的一连串连锁反应。

唤醒后谁能优先抢到资源，那就得看调度的时机以及调度的机制了。

现在 shell 进程，通过 `read` 函数，中间经过了层层封装，以及后面经过了阻塞与唤醒后，终于把键盘输入的字符，由 `tty` 中的 `secondary` 队列，读取并存放与 `buf` 指向的内存地址处。

== 解析并执行shell命令

=== 解析shell类型

```sh
[root@linux0.11] cat info.txt | wc -l
```

回到shell程序
#figure(
```c
// xv6-public sh.c
int main(void) {
    static char buf[100];
    // 读取命令
    while(getcmd(buf, sizeof(buf)) >= 0){
        // 创建新进程
        if(fork() == 0)
            // 执行命令
            runcmd(parsecmd(buf));
        // 等待进程退出
        wait();
    }
}
```,
caption: [shell - runcmd]
)

解析并执行也就是上述函数中的 `runcmd` 命令。

`parsecmd` 函数会将读取到 `buf` 的字符串命令做解析，生成一个 `cmd` 结构的变量，传入 `runcmd` 函数中。

#figure(
```c
// xv6-public sh.c
void runcmd(struct cmd *cmd) {
    ...
    switch(cmd->type) {
        ...
        case EXEC:
        ecmd = (struct execcmd*)cmd;
        ...
        exec(ecmd->argv[0], ecmd->argv);
        ...
        break;

        case REDIR: ...
        case LIST: ...
        case PIPE: ...
        case BACK: ...
    }
}
```,
caption: [runcmd]
)

然后`runcmd` 根据 `cmd` 的 `type` 字段，来判断应该如何执行这个命令。

- 直接执行，也即 `EXEC`。
- 命令中有分号 `;` 说明是多条命令的组合，那么就当作 `LIST` 拆分成多条命令依次执行。
- 命令中有竖线 `|` 说明是管道命令，那么就当作 `PIPE` 拆分成两个并发的命令，同时通过管道串联起输入端和输出端，来执行。

`cat info.txt | wc -l`这个命令，很显然就是个管道命令。

#tip("Tip")[
所谓管道，也就是上述命令中的 `|`，实现的就是将 `|` 左边的程序的输出（`stdout`）作为 `|` 右边的程序的输入（`stdin`）
]

=== 管道

走到 `runcmd` 方法中的 `PIPE` 这个分支。

#figure(
```c
// xv6-public sh.c
void runcmd(struct cmd *cmd) {
    ...
    int p[2];
    ...
    case PIPE:
        pcmd = (struct pipecmd*)cmd;
        pipe(p);
        if(fork() == 0) {
            close(1);
            dup(p[1]);
            close(p[0]);
            close(p[1]);
            runcmd(pcmd->left);
        }
        if(fork() == 0) {
            close(0);
            dup(p[0]);
            close(p[0]);
            close(p[1]);
            runcmd(pcmd->right);
        }
        close(p[0]);
        close(p[1]);
        wait(0);
        wait(0);
        break;
    ...
}
```,
caption: [runcmd - pipe]
)

构造了一个大小为 `2` 的数组 `p`，然后作为 `pipe` 的参数传了进去。`pipe()`最终会调用到系统调用的 `sys_pipe`，通过 `man page` 查看 `pipe` 的用法与说明。

#figure(caption: [])[#image("images/chapter39-1.png", width: 80%)]

可以看到，`pipe` 做了两件事
- 创建一个管道
- 将传入数组 `p` 的 `p[0]` 指向这个管道的读口，`p[1]` 指向这个管道的写口。
#figure(caption: [])[#image("images/chapter39-2.png", width: 60%)]

*管道的本质是一个文件*，但是是属于*管道类型的文件*，所以它更本质上是*一块内存*。

这块内存被当作管道文件对上层提供了像访问文件一样的读写接口，只不过其中一个进程只能读，另一个进程只能写，所以再次抽象一下就像一个管道一样，数据从一端流向了另一段。

#figure(
```c
// xv6-public sh.c
void runcmd(struct cmd *cmd) {
    ...
    int p[2];
    ...
    case PIPE:
        pcmd = (struct pipecmd*)cmd;
        pipe(p);
        if(fork() == 0) {
            close(1);
            dup(p[1]);
            close(p[0]);
            close(p[1]);
            runcmd(pcmd->left);
        }
        if(fork() == 0) {
            close(0);
            dup(p[0]);
            close(p[0]);
            close(p[1]);
            runcmd(pcmd->right);
        }
        close(p[0]);
        close(p[1]);
        wait(0);
        wait(0);
        break;
    ...
}
```,
caption: [runcmd - pipe]
)

在调用完 `pipe` 搞出了这样一个管道并绑定了 `p[0]` 和 `p[1]` 之后，又分别通过 `fork` 创建了两个进程，其中*第一个进程执行了管道左边的程序*，*第二个进程执行了管道右边的程序*。

由于 `fork` 出的子进程会原封不动复制父进程打开的文件描述符，所以目前的状况如下图所示。

#figure(caption: [])[#image("images/chapter39-3.png", width: 60%)]

由于每个进程，一开始都打开了 0 号标准输入文件描述符，1 号标准输出文件描述符和 2 号标准错误输出文件描述符，所以目前把文件描述符都展开。（父进程的就省略了）
#figure(caption: [])[#image("images/chapter39-4.png", width: 60%)]

左边子进程随后进行了如下操作。

#figure(
```c
// fs/pipe.c
...
if(fork() == 0) {
    close(1);
    dup(p[1]);
    close(p[0]);
    close(p[1]);
    runcmd(pcmd->left);
}
...
```,
caption: [pipe - 左]
)

即关闭（`close`）了 1 号标准输出文件描述符，复制（`dup`）了 `p[1]` 并填充在了 `1` 号文件描述符上（因为刚刚关闭后空缺出来了），然后又把 `p[0]` 和 `p[1]` 都关闭（`close`）了。最终的效果就是，*将 1 号文件描述符，也就是标准输出，指向了 `p[1]` 管道的写口*，也就是 `p[1]` 原来所指向的地方。

#figure(caption: [])[#image("images/chapter39-5.png", width: 60%)]

同理，右边进程也进行了类似的操作。

#figure(
```c
// fs/pipe.c
...
if(fork() == 0) {
    close(0);
    dup(p[0]);
    close(p[0]);
    close(p[1]);
    runcmd(pcmd->right);
}
...
```,
caption: [pipe - 右]
)

只不过，最终是将 0 号标准输入指向了管道的读口。
#figure(caption: [])[#image("images/chapter39-6.png", width: 60%)]

再看父进程。

#figure(
```c
// xv6-public sh.c
void runcmd(struct cmd *cmd) {
    ...
    pipe(p);
    if(fork() == 0) {...}
    if(fork() == 0) {...}
    // 父进程
    close(p[0]);
    close(p[1]);
    ...
}
```,
caption: [pipe - 父]
)

父进程仅仅是将 `p[0]` 和 `p[1]` 都关闭掉了，父进程执行的 `pipe`仅仅是为两个子进程申请的文件描述符。

那么忽略父进程，最终，其实就是创建了两个进程，左边的进程的标准输出指向了管道（写），右边的进程的标准输入指向了同一个管道（读），看起来就是下面的样子。

#figure(caption: [])[#image("images/chapter39-7.png", width: 60%)]

管道的本质就是一个文件，只不过是管道类型的文件，再本质就是一块内存。所以这一顿操作，其实就是把两个进程的文件描述符，指向了一个文件罢了。

看看 `sys_pipe` 函数的细节。

#figure(
```c
// fs/pipe.c
int sys_pipe(unsigned long * fildes) {
    struct m_inode * inode;
    struct file * f[2];
    int fd[2];

    for(int i=0,j=0; j<2 && i<NR_FILE; i++)
        if (!file_table[i].f_count)
            (f[j++]=i+file_table)->f_count++;
    ...
    for(int i=0,j=0; j<2 && i<NR_OPEN; i++)
        if (!current->filp[i]) {
            current->filp[ fd[j]=i ] = f[j];
            j++;
        }
    ...
    if (!(inode=get_pipe_inode())) {
        current->filp[fd[0]] = current->filp[fd[1]] = NULL;
        f[0]->f_count = f[1]->f_count = 0;
        return -1;
    }
    f[0]->f_inode = f[1]->f_inode = inode;
    f[0]->f_pos = f[1]->f_pos = 0;
    f[0]->f_mode = 1;       /* read */
    f[1]->f_mode = 2;       /* write */
    put_fs_long(fd[0],0+fildes);
    put_fs_long(fd[1],1+fildes);
    return 0;
}
```,
caption: [sys_pipe]
)

和进程打开一个文件的步骤是差不多的，下图是进程打开一个文件时的步骤。
#figure(caption: [])[#image("images/chapter39-8.png", width: 70%)]

而 `pipe` 方法与之相同的是，都是从进程中的文件描述符表 `filp` 数组和系统的文件系统表 `file_table` 数组中寻找空闲项并绑定。

不同的是，打开一个文件的前提是文件已经存在了，根据文件名找到这个文件，并提取出它的 `inode` 信息，填充好 `file` 数据。而 `pipe` 方法中并不是打开一个已存在的文件，而是创建一个新的管道类型的文件，具体是通过 `get_pipe_inode` 方法，返回一个 `inode` 结构。然后，填充了两个 `file` 结构的数据，都指向了这个 `inode`，其中一个的 `f_mode` 为 `1` 也就是写，另一个是 `2` 也就是读。（`f_mode` 为文件的操作模式属性，也就是 `RW` 位的值）

创建管道的方法 `get_pipe_inode` 方法如下。

#figure(
```c
// fs.h
#define PIPE_HEAD(inode) ((inode).i_zone[0])
#define PIPE_TAIL(inode) ((inode).i_zone[1])

// inode.c
struct m_inode * get_pipe_inode(void) {
    struct m_inode *inode = get_empty_inode()；
    inode->i_size=get_free_page()；
    inode->i_count = 2; /* sum of readers/writers */
    PIPE_HEAD(*inode) = PIPE_TAIL(*inode) = 0;
    inode->i_pipe = 1;
    return inode;
}
```,
caption: [get_pipe_inode]
)

可以看出，正常文件的 `inode` 中的 `i_size` 表示文件大小，而管道类型文件的 `i_size` 表示供管道使用的这一页内存的起始地址。

回到最开始的 `runcmd` 方法。

#figure(
```c
// xv6-public sh.c
void runcmd(struct cmd *cmd) {
    ...
    switch(cmd->type) {
        ...
        case EXEC:
        ecmd = (struct execcmd*)cmd;
        ...
        exec(ecmd->argv[0], ecmd->argv);
        ...
        break;

        case REDIR: ...
        case LIST: ...
        case PIPE: ...
        case BACK: ...
    }
}
```,
caption: [runcmd]
)

如果展开每个 `switch` 分支会发现，不论是更换当前目录的 `REDIR` 也就是 `cd` 命令，还是用分号分隔开的 `LIST` 命令，还是上面讲到的 `PIPE` 命令，最终都会被拆解成一个个可以被解析为 `EXEC` 类型的命令。 `EXEC` 类型会执行到 `exec` 这个方法，在 Linux 0.11 中，最终会通过系统调用执行到 `sys_execve` 方法。

#pagebreak()
