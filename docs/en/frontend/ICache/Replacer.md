# Replacer {#sec:icache-replacer}

ICache replacer uses PLRU update algorithm.

Similar to [@sec:icache-metaarray-interleave] [MetaArray interleave](Array.md#metaarray-interleave-secicache-metaarray-interleave), considering each fetch may access two consecutive cachelines, one replacer is used for odd addresses and another for even addresses. During touch and victim selection, corresponding replacer is selected by address parity.

## PLRU Algorithm {#sec:icache-replacer-plru}

PLRU uses a tree structure to best-effort track the least recently used line. With ICache default 4-way configuration as example, PLRU uses 3 bits to track usage of 4 ways, as shown in [@fig:icache-plru]. When one state bit is 0, it means lines in left subtree are less recently used; when it is 1, it means lines in right subtree are less recently used. On each access, state bits are updated according to accessed way position in the tree. For example, if `way0` is accessed, update `state[0]=1` (meaning between `way0` and `way1`, `way1` is less recently used) and `state[1]=1` (meaning between `way0/1` and `way2/3`, `way2/3` are less recently used). When selecting victim, traverse from root following state bits until leaf, then victim way is obtained.

![PLRU algorithm illustration](../figure/ICache/plru.png){#fig:icache-plru}

Please also refer to rocket-chip implementation.

## touch {#sec:icache-replacer-touch}

Replacer has two touch ports corresponding to two cachelines of one fetch request. Touch update is sent to corresponding replacer according to touch address parity.

## victim {#sec:icache-replacer-victim}

Replacer has only one victim port because at any time only one MSHR request is sent to bus. Victim waymask is similarly selected from corresponding replacer by address parity. Internal touch update is then performed for that replacer in next cycle.
