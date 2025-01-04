#import "../template.typ":*

= shell程序

以xv6里的shell实现为例，仍然去掉多余的校验逻辑

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
caption: [xv6 - shell简化版]
)

总得来说，shell 程序就是个死循环，在死循环里面，shell 就是不断读取（`getcmd`）用户输入的命令，创建一个新的进程（`fork`），在新进程里执行（`runcmd`）刚刚读取到的命令，最后等待（`wait`）进程退出，再次进入读取下一条命令的循环中。

shell 就是不断 fork + execve 完成执行一个新程序的功能的，那 `execve` 就藏在 `runcmd` 代码了。

#figure(
```c
void runcmd(struct cmd *cmd) {
    ...
    struct execcmd ecmd = (struct execcmd*)cmd;
    ...
    exec(ecmd->argv[0], ecmd->argv);
    ...
}
```,
caption: [runcmd]
)

省略了很多代码，比如遇到管道命令 PIPE，遇到命令集合 LIST 时的处理逻辑，我们仅仅看单纯执行一条命令的逻辑。就是简简单单调用了个 `exec` 函数

#pagebreak()
