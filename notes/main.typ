#import "template.typ": *

#show: template.with(
  // 笔记标题
  title: [Linux 0.11 - RTFS],
  // 在页眉展示的短标题（选填）
  short-title: "RTFS",
  // 笔记描述（选填）
  description: [
    Linux 0.11 源码阅读。
  ],
  // 笔记创建日期（选填）
  date: datetime(year: 2024, month: 12, day: 31),
  // 作者信息（除 name 外，其他参数选填）
  authors: (
    (
      name: "0x1B05",
      github: "https://github.com/0x1B05",
      homepage: "https://github.com/0x1B05",
    ),
  ),


  // 页面尺寸，同时会影响页边距。
  paper-size: "a4",

  // 中英文文本和代码的字体
  fonts: (
    (
      en-font: "Libertinus Serif",
      zh-font: "Noto Sans CJK SC",
      code-font: "DejaVu Sans Mono",
    )
  ),
  
  // 主题色
  accent: orange,
  // 封面背景图片（选填图片路径或 none）
  cover-image: "./figures/cover-image.png",
  // 正文背景颜色（选填 HEX 颜色或 none）
  background-color: "#FAF9DE"
)

#include "content/第00回 全局概览.typ"
#include "content/第01回 最开始的两行代码.typ"
#include "content/第02回 自己给自己挪地儿.typ"
#include "content/第03回 做好最最基础的准备工作.typ"
#include "content/第04回 把自己在硬盘里的其他部分也放到内存来.typ"
#include "content/第05回 进入保护模式前的最后一次折腾内存.typ"
#include "content/第06回 先解决段寄存器的历史包袱问题.typ"
#include "content/第07回 六行代码就进入了保护模式.typ"
#include "content/第08回 烦死了又要重新设置一遍idt和gdt.typ"
#include "content/第09回 Intel 内存管理两板斧：分段与分页.typ"
#include "content/第10回 进入main函数前的最后一跃.typ"
#include "content/第11回 main函数.typ"
#include "content/第12回 管理内存前先划分出三个边界值.typ"
#include "content/第13回 操作系统就用一张大表管理内存.typ"
#include "content/第14回 你的键盘是什么时候生效的.typ"
#include "content/第15回 读取硬盘前的准备工作有哪些.typ"
#include "content/第16回 按下键盘后为什么屏幕上就会有输出.typ"
#include "content/第17回 获取时间(time_init).typ"
#include "content/第18回 进程调度(sched_init).typ"
#include "content/第19回 缓冲区(buffer_init).typ"
#include "content/第20回 硬盘(hd_init).typ"
#include "content/第21回 新进程的诞生全局概述.typ"
#include "content/第22回 从内核态到用户态.typ"
#include "content/第23回 进程调度.typ"
#include "content/第24回 进程调度(定时器).typ"
#include "content/第25回 通过fork看系统调用.typ"
#include "content/第26回 fork中进程信息的复制.typ"
#include "content/第27回 通过fork看进程的内存规划.typ"
#include "content/第28回 fork的写时复制.typ"
#include "content/第29回 拿到硬盘信息.typ"
#include "content/第30回 加载根文件系统.typ"
#include "content/第31回 打开终端设备文件.typ"
#include "content/第32回 进程2的创建.typ"
#include "content/第33回 execve.typ"
#include "content/第34回 缺页中断.typ"
#include "content/第35回 shell程序.typ"
#include "content/第36回 用键盘输入一条命令.typ"
#include "content/第37回 shell程序读取命令.typ"
#include "content/第38回 进程的阻塞与唤醒.typ"
#include "content/第39回 解析并执行shell命令.typ"
#include "content/第40回 读硬盘数据全流程.typ"
#include "content/第41回 信号.typ"
