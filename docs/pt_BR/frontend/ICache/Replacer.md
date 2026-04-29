# Replacer 子模块文档

采用 PLRU 更新算法，考虑到每次取指可能访问连续的 doubleline，对于奇地址和偶地址设置两个 replacer，在进行 touch 和 victim
时根据地址的奇偶分别更新 replacer。

![PLRU 算法示意](../figure/ICache/Replacer/plru.png)

## touch

Replacer 具有两个 touch 端口，用以支持双行，根据 touch 的地址奇偶分配到对应的 replacer 进行更新。

## victim

Replacer 只有一个 victim 端口，因为同时只有一个 MSHR 会写入 SRAM，同样根据地址的奇偶从对应的 replacer 获取
waymask。并且在下一拍再进行 touch 操作更新 replacer。
