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

#include "content/第0回 全局概览.typ"
#include "content/第1回 开机->内核.typ"
#include "content/第2回 main里面的初始化.typ"
#include "content/第3回 新进程的诞生.typ"
#include "content/第4回 init进程.typ"
#include "content/第5回 缺页中断.typ"
#include "content/第6回 shell命令全流程.typ"
#include "content/第7回 读硬盘数据全流程.typ"
#include "content/第8回 信号.typ"
