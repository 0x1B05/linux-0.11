#import "../template.typ":*

= 进程的阻塞与唤醒

`sleep_on` 和 `wake_up` 是进程的阻塞与唤醒机制的实现

表示进程的数据结构是 `task_struct`，其中有一个 `state` 字段表示进程的状态，它在 Linux 0.11 里有五种枚举值。

#figure(
```c
// shed.h
#define TASK_RUNNING 0      // 运行态
#define TASK_INTERRUPTIBLE 1    // 可中断等待状态。
#define TASK_UNINTERRUPTIBLE 2  // 不可中断等待状态
#define TASK_ZOMBIE 3       // 僵死状态
#define TASK_STOPPED 4      // 停止
```,
caption: [task_struct->state]
)

当进程首次被创建时，也就是 fork 函数执行后，它的初始状态是 0，也就是运行态。

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

Linux 0.11 中的阻塞与唤醒，就是 `sleep_on` 和 `wake_up` 函数。

其中 `sleep_on` 函数将 `state` 变为 `TASK_UNINTERRUPTIBLE`。

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
caption: [sleep_on]
)

而 `wake_up` 函数将 `state` 变回为 `TASK_RUNNING`，也就是 `0`。

#figure(
```c
// sched.c
void wake_up (struct task_struct **p) {
    (**p).state = 0;
}
```,
caption: [wake_up]
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

通过 `tmp = *p` 和 `*p = current` 两个赋值操作，此时： `tmp = NULL`, `*p = 当前任务`, 同时也使得 `proc_list` 指向了当前任务的 `task_struct`。

#figure(caption: [])[#image("images/chapter38-1.png", width: 60%)]

当有另一个进程调用了 `tty_read` 读取了同一个 `tty` 的数据时，就需要再次 `sleep_on`，此时携带的 `*p` 就是一个指向了之前的"当前任务"的结构体。那么经过 `tmp = *p` 和 `*p = current` 两个赋值操作后，会变成这个样子。
#figure(caption: [])[#image("images/chapter38-2.png", width: 60%)]

也就是说，通过每一个当前任务所在的代码块中的 `tmp` 变量，总能找到上一个正在同样等待一个资源的进程，因此也就形成了一个链表。

当某进程调用了 `wake_up` 函数唤醒 `proc_list` 上指向的第一个任务时，改任务变会在 `sleep_on` 函数执行完 `schedule()` 后被唤醒并执行下面的代码，把 `tmp` 指针指向的上一个任务也同样唤醒。

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

唤醒其实就是把 `state` 变成 `0` 而已。

而上一个进程唤醒后，和这个被唤醒的进程一样，也会走过它自己的 `sleep_on` 函数的后半段，把它的上一个进程，也就是上上一个进程唤醒。通过一个 `wake_up` 函数，以及上述这种 `tmp` 变量的巧妙设计，我们就能制造出唤醒的一连串连锁反应。

唤醒后谁能优先抢到资源，那就得看调度的时机以及调度的机制了。

现在 shell 进程，通过 read 函数，中间经过了层层封装，以及后面经过了阻塞与唤醒后，终于把键盘输入的字符，成功由 `tty` 中的 `secondary` 队列，读取并存放与 `buf` 指向的内存地址处。

#pagebreak()
