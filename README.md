# E-Gost

一个自已玩儿的转发！
20250831更新为Gost 3.2.4 Latest 版
自定义为：

Gost TCP+UDP 端口转发 1.1 Pro版  


目前够用了，无特别bug之外，短时不更新了！

反正我能用，你能不能用，我不知道！

使用前注意安装相关依赖：我也放个依赖的脚本吧：

---------------------------------------------------------------------------------------------------------------------------------------
apt-get -y update && apt-get -y upgrade && apt update -y && apt install -y curl && apt install -y wget && apt install -y socat && apt-get install cron && apt-get install sudo && apt install -y jq && update-grub

---------------------------------------------------------------------------------------------------------------------------------------

脚本

启动脚本

wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/xtonly/E-Gost/master/gost.sh && chmod +x gost.sh && ./gost.sh

再次运行本脚本只需要输入./gost.sh回车,或者运行脚本 9 选项，下次root直接输入 g 打开脚本！

此脚本用gost 3.2.4 版本，如果没有大的变化不会更新为新的版本，跟不跟随官方更新就随缘了！
