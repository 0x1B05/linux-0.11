#import "../template.typ": *

= 进入main函数前的最后一跃

#figure(
```asm
after_page_tables:
    push 0
    push 0
    push 0
    push L6
    push _main
    jmp setup_paging
...
setup_paging:
    ...
    ret
```,
caption: [head - 跳转main]
)

#figure(caption: [])[#image("images/chapter10-1.png", width: 30%)]

#h(2em)`setup_paging` 最后一个指令是 `ret`，也就是我们上一回讲的设置分页的代码的最后一个指令，形象地说它叫返回指令，但 CPU 并不知道该返回到哪里执行，只是机械地把栈顶的元素值当做返回地址，跳转去那里执行。

再具体说是，把 `esp` 寄存器（栈顶地址）所指向的内存处的值，赋值给 `eip` 寄存器，而 `cs:eip` 就是 CPU 要执行的下一条指令的地址。而此时栈顶刚好是 `main.c` 里写的 `main` 函数的内存地址，是我们刚刚特意压入栈的，所以 CPU 就理所应当跳过来了。

压入栈的 `L6` 是用作当 `main` 函数返回时的跳转地址，但由于在操作系统层面的设计上，`main` 是绝对不会返回的，所以也就没用了。而其他的三个压栈的 `0`，本意是作为 `main` 函数的参数，但实际上似乎也没有用到，所以也不必关心。

总结进入内核前的准备工作：
#figure(caption: [])[#image("images/chapter10-2.png", width: 50%)]
内存布局
#figure(caption: [])[#image("images/chapter10-3.png", width: 60%)]

== 扩展资料
有关 `call` 和 `ret` 指令： Intel 1 Chapter 6.4 CALLING PROCEDURES USING CALL AND RET
#figure(caption: [])[#image("images/chapter10-4.png", width: 80%)]
以及改变段基址的 `far call` 和 `far ret`：
#figure(caption: [])[#image("images/chapter10-5.png", width: 80%)]
压栈和出栈的具体过程图示：
#figure(caption: [])[#image("images/chapter10-6.png", width: 80%)]
我们本文就是左边的那一套，把 `main` 函数地址值当做 `Calling EIP` 压入栈，仿佛是执行了 `call` 指令调用了一个函数一样，然后 `ret` 的时候就把栈顶的那个 `Calling EIP` 也就是 `main` 函数地址弹出栈，存入 `EIP` 寄存器，这样 CPU 就相当于“返回”到了 `main` 函数开始执行。

#pagebreak()
